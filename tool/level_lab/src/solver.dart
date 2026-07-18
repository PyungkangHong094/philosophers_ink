/// 스트로크 탐색 솔버 (레벨 랩 L1, docs/LEVEL_LAB.md §1).
///
/// (a) 격자 스냅 편향 무작위 샘플링으로 클리어 후보를 찾고 → (b) 상위 해를 국소 정련
/// (좌표 섭동·선분 축소·선분 제거)으로 잉크를 줄인다. 각 후보는 헤드리스 롤아웃으로 승리
/// 판정한다. 산출: solvable / min_ink / effort(첫 해까지 롤아웃 수) / 상위 N개 해 아카이브.
///
/// 결정성: [SolverConfig.seed] 고정 → 재실행 동일 결과. 모든 무작위는 [DeterministicRng]
/// 단일 인스턴스에서만 나온다.
library;

import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/gameplay/headless_session.dart';
import 'package:philosophers_ink/level/level_model.dart';

import 'candidate.dart';
import 'rollout.dart';

class SolverConfig {
  final int seed;

  /// 샘플링 롤아웃 상한 (docs §1 기본 2,000).
  final int rolloutBudget;

  /// 정련 롤아웃 상한.
  final int refineBudget;
  final int tickCap;
  final int stallTicks;

  /// 선분 개수 상한 k (docs §1: k≤4부터).
  final int maxStrokes;

  /// 좌표 격자 스냅(셀). 탐색 공간 축소.
  final int snap;

  /// 아카이브·출력할 상위 해 수.
  final int topK;

  /// 샘플링 중 이만큼 해를 모으면 정련으로 넘어간다 (쉬운 레벨 조기 종료).
  final int collectTarget;

  const SolverConfig({
    this.seed = 0x5EED1A5,
    this.rolloutBudget = 2000,
    this.refineBudget = 700,
    this.tickCap = 1400,
    // 낙하 시간(≈285틱)보다 충분히 커야 한다 — 작으면 물질 착수 전에 중단해 오검출.
    // 다중 플라스크의 늦은 셋째 플라스크(L007: 679틱 클리어)까지 잡으려면 ≥350 필요.
    this.stallTicks = 400,
    this.maxStrokes = 4,
    this.snap = 4,
    this.topK = 5,
    this.collectTarget = 15,
  });

  SolverConfig copyWith({
    int? seed,
    int? rolloutBudget,
    int? refineBudget,
    int? tickCap,
    int? stallTicks,
    int? maxStrokes,
  }) =>
      SolverConfig(
        seed: seed ?? this.seed,
        rolloutBudget: rolloutBudget ?? this.rolloutBudget,
        refineBudget: refineBudget ?? this.refineBudget,
        tickCap: tickCap ?? this.tickCap,
        stallTicks: stallTicks ?? this.stallTicks,
        maxStrokes: maxStrokes ?? this.maxStrokes,
        snap: snap,
        topK: topK,
        collectTarget: collectTarget,
      );
}

/// 후보 + 롤아웃 결과 (적합도 풀 원소). 적합도↓·잉크↑ 순으로 정렬한다.
class _Scored {
  final Candidate candidate;
  final RolloutResult result;
  const _Scored(this.candidate, this.result);
}

/// [s]를 적합도 상위 [cap]개 풀에 넣는다. 후보 문자열 중복은 더 나은 것만 유지.
/// 정렬 기준: 적합도 내림차순 → 잉크 오름차순.
void _offerPool(List<_Scored> pool, _Scored s, int cap) {
  final key = s.candidate.toString();
  final existing = pool.indexWhere((e) => e.candidate.toString() == key);
  if (existing >= 0) {
    if (_better(s, pool[existing])) {
      pool[existing] = s;
    } else {
      return;
    }
  } else {
    pool.add(s);
  }
  pool.sort((a, b) {
    final f = b.result.fitness.compareTo(a.result.fitness);
    return f != 0 ? f : a.result.inkUsed.compareTo(b.result.inkUsed);
  });
  if (pool.length > cap) pool.removeRange(cap, pool.length);
}

bool _better(_Scored a, _Scored b) =>
    a.result.fitness > b.result.fitness ||
    (a.result.fitness == b.result.fitness &&
        a.result.inkUsed < b.result.inkUsed);

/// 발견한 해 1개 (후보 + 실측 잉크·클리어 틱).
class FoundSolution {
  final Candidate candidate;
  final int ink;
  final int ticks;
  const FoundSolution(this.candidate, this.ink, this.ticks);
}

class SolveResult {
  final int levelId;
  final String name;
  final int chapter;
  final bool solvable;

  /// 발견 해 중 최소 잉크 (미발견 시 null).
  final int? minInk;

  /// 첫 해 발견까지 소요한 샘플링 롤아웃 수 (미발견 시 null).
  final int? effort;

  /// 실제 수행한 총 롤아웃 수 (샘플링+정련).
  final int rollouts;

  /// 상위 해 아카이브 (잉크 오름차순).
  final List<FoundSolution> solutions;

  final int elapsedMs;
  final Map<InkType, int> budget;

  const SolveResult({
    required this.levelId,
    required this.name,
    required this.chapter,
    required this.solvable,
    required this.minInk,
    required this.effort,
    required this.rollouts,
    required this.solutions,
    required this.elapsedMs,
    required this.budget,
  });

  Map<String, dynamic> toJson() => {
        'level': levelId,
        'name': name,
        'chapter': chapter,
        'solvable': solvable,
        'min_ink': minInk,
        'effort': effort,
        'rollouts': rollouts,
        'elapsed_ms': elapsedMs,
        'budget': {
          for (final e in budget.entries) inkKey(e.key): e.value,
        },
        'solutions': [
          for (final s in solutions)
            {
              'ink': s.ink,
              'ticks': s.ticks,
              ...s.candidate.toJson(),
            }
        ],
      };
}

/// 한 레벨을 솔브한다. [session]은 재사용(내부 reset)하고 없으면 새로 만든다.
SolveResult solveLevel(Level level, SolverConfig cfg) {
  final sw = Stopwatch()..start();
  final session = HeadlessSession(level);
  final rng = DeterministicRng(cfg.seed);
  final rolloutCfg = RolloutConfig(tickCap: cfg.tickCap, stallTicks: cfg.stallTicks);
  // 빈-후보 프로브 전용 설정: 정체 중단 없이(stall 무한) 넉넉한 틱까지 — 입자 더미 확산이
  // 느린 레벨(예 L004 ≈1936틱)도 0-잉크 클리어를 정확히 검출한다. 탐색 rollout보다 관대.
  final probeCap = cfg.tickCap < 2400 ? 2400 : cfg.tickCap;
  final probeCfg = RolloutConfig(tickCap: probeCap, stallTicks: probeCap);
  final sampler = _Sampler(level, session, cfg);

  // 승리 해 아카이브 (min_ink·출력용). 후보 문자열 키로 중복 제거.
  final archive = <String, FoundSolution>{};
  // 적합도 상위 풀 — **근접해(부분해)까지** 담아 정련 시드로 쓴다. 희소 보상(다중
  // 플라스크)에서 이게 핵심: [25,25,0] 같은 근접해를 언덕오르기해 [25,25,25]로 민다.
  const poolCap = 8;
  final pool = <_Scored>[];
  int? effort;
  var rollouts = 0;

  // 후보 1개 평가 + 아카이브·풀·effort 갱신. 승리 시 아카이브에 기록.
  RolloutResult step(Candidate c, [RolloutConfig? cfgOverride]) {
    final r = rollout(session, c, cfgOverride ?? rolloutCfg);
    rollouts++;
    if (r.solved) {
      effort ??= rollouts;
      final key = c.toString();
      final prev = archive[key];
      if (prev == null || r.inkUsed < prev.ink) {
        archive[key] = FoundSolution(c, r.inkUsed, r.ticks);
      }
    }
    _offerPool(pool, _Scored(c, r), poolCap);
    return r;
  }

  // --- 빈 후보 프로브: 잉크 0으로도 클리어되는가(입자 더미 확산 치즈, GDD 3.3).
  // 다수 튜토리얼 레벨이 여기서 즉시 solvable로 확정된다. 잉크 0 클리어는 별점 밸런스
  // 이슈이므로 리포트에 명시한다. 관대한 probeCfg로 정체 중단 오검출을 피한다.
  const inkFloor = 8;
  step(const Candidate([]), probeCfg);

  int minArchiveInk() => archive.isEmpty
      ? 1 << 30
      : archive.values.map((s) => s.ink).reduce((a, b) => a < b ? a : b);

  // --- (a) 편향 무작위 샘플링: 적합도 풀을 채운다 ---
  while (rollouts < cfg.rolloutBudget) {
    step(sampler.sample(rng));
    // 승리 해를 충분히 모았으면 조기 종료(쉬운 레벨).
    if (archive.length >= cfg.collectTarget) break;
    // 빈-후보가 이미 0-잉크로 클리어 → 더 나은 해 없음. 아카이브 다양성만 소량 확보 후 종료.
    if (minArchiveInk() <= inkFloor && rollouts >= 25) break;
  }

  // --- (b) 적합도 언덕오르기 정련 (근접해 → 승리해, 그리고 잉크 최소화) ---
  // 정련이 의미 있는 경우: 아직 미해결이거나(풀의 근접해를 밀어야 함),
  // 해는 있으나 잉크가 바닥(inkFloor) 위라 줄일 여지가 있을 때.
  final bestInk = minArchiveInk();
  final worthRefine = pool.isNotEmpty && (archive.isEmpty || bestInk > inkFloor);
  if (worthRefine) {
    // 개선 정체 조기 종료: 이미 승리 해가 있고 [patience]틱 동안 min_ink가 안 줄면 중단.
    // (해가 아직 없으면 계속 근접해를 민다 — 첫 해 발견이 우선.)
    const patience = 150;
    var bestInkSeen = archive.isEmpty
        ? 1 << 30
        : archive.values.map((s) => s.ink).reduce((a, b) => a < b ? a : b);
    var sinceImprove = 0;
    final seeds = [...pool]; // 이미 적합도순 정렬됨.
    final seedCount = seeds.length < 6 ? seeds.length : 6;
    var refineLeft = cfg.refineBudget;
    outer:
    for (var si = 0; si < seedCount && refineLeft > 0; si++) {
      var current = seeds[si];
      final perSeed = refineLeft ~/ (seedCount - si);
      for (var i = 0; i < perSeed; i++) {
        final mut = sampler.mutate(current.candidate, rng);
        final r = step(mut);
        refineLeft--;
        // 엘리트 언덕오르기: 적합도↑ 또는 (동률 & 잉크≤)면 이동(평지 드리프트 허용).
        if (r.fitness > current.result.fitness ||
            (r.fitness == current.result.fitness &&
                r.inkUsed <= current.result.inkUsed)) {
          current = _Scored(mut, r);
        }
        // 정체 카운터: 승리 해가 생겼거나 min_ink가 줄면 리셋.
        final curBest = archive.isEmpty
            ? 1 << 30
            : archive.values.map((s) => s.ink).reduce((a, b) => a < b ? a : b);
        if (curBest < bestInkSeen) {
          bestInkSeen = curBest;
          sinceImprove = 0;
        } else {
          sinceImprove++;
        }
        if (archive.isNotEmpty && sinceImprove >= patience) break outer;
      }
    }
  }

  sw.stop();
  final sols = archive.values.toList()
    ..sort((a, b) => a.ink.compareTo(b.ink));
  final top = sols.take(cfg.topK).toList();

  return SolveResult(
    levelId: level.meta.id,
    name: level.meta.name,
    chapter: level.meta.chapter,
    solvable: sols.isNotEmpty,
    minInk: sols.isEmpty ? null : sols.first.ink,
    effort: effort,
    rollouts: rollouts,
    solutions: top,
    elapsedMs: sw.elapsedMilliseconds,
    budget: level.inkBudget,
  );
}

/// 레벨 지오메트리에 편향된 스트로크 샘플러.
class _Sampler {
  final SolverConfig cfg;
  final List<InkType> inks;
  final bool hasGravity;

  // 소스(방출구)·싱크(플라스크) 앵커.
  final List<int> srcX = [];
  final List<int> sinkX = [];

  /// 플라스크 중심 y (램프 도착 앵커). 상단/하단 플라스크를 대칭적으로 다룬다.
  final List<int> sinkCy = [];

  // 활성 바운딩 박스.
  late final int xLo, xHi, yLo, yHi;

  static const int _w = SimConstants.gridWidth;
  static const int _h = SimConstants.gridHeight;

  // 중력 탭 후보 틱. 이른 값(즉시 반전)부터 늦은 값(한 플라스크를 먼저 채운 뒤
  // 반전해 다른 플라스크로) 까지 — L011처럼 순차 충전이 필요한 레벨을 위해 후반 틱 포함.
  static const List<int> _tapTicks = [0, 60, 150, 300, 450, 600, 800];

  _Sampler(Level level, HeadlessSession session, this.cfg)
      : inks = session.visibleInks,
        hasGravity = session.hasGravityFlip {
    var minX = _w, maxX = 0, minY = _h, maxY = 0;
    for (final e in level.emitters) {
      final cx = e.x + e.width ~/ 2;
      srcX.add(cx);
      minX = cx < minX ? cx : minX;
      maxX = cx > maxX ? cx : maxX;
      final by = e.y + 4;
      minY = by < minY ? by : minY;
    }
    for (final f in level.flasks) {
      final cx = f.x + f.w ~/ 2;
      sinkX.add(cx);
      sinkCy.add(f.y + f.h ~/ 2);
      minX = f.x < minX ? f.x : minX;
      maxX = f.x + f.w > maxX ? f.x + f.w : maxX;
      minY = f.y < minY ? f.y : minY;
      maxY = f.y + f.h > maxY ? f.y + f.h : maxY;
    }
    // 방출구·플라스크가 없을 리 없지만 방어.
    if (srcX.isEmpty) srcX.add(_w ~/ 2);
    if (sinkX.isEmpty) {
      sinkX.add(_w ~/ 2);
      sinkCy.add(_h ~/ 2);
    }
    xLo = _clampX(minX - 24);
    xHi = _clampX(maxX + 24);
    yLo = _clampY(minY);
    yHi = _clampY(maxY == 0 ? _h - 8 : maxY);
  }

  int _clampX(int v) => v < 0 ? 0 : (v > _w - 1 ? _w - 1 : v);
  int _clampY(int v) => v < 0 ? 0 : (v > _h - 1 ? _h - 1 : v);

  int _snap(int v, int lo, int hi) {
    final s = cfg.snap;
    var q = ((v + s ~/ 2) ~/ s) * s;
    if (q < lo) q = lo;
    if (q > hi) q = hi;
    return q;
  }

  int _rand(DeterministicRng rng, int lo, int hi) =>
      hi <= lo ? lo : lo + rng.nextInt(hi - lo + 1);

  int _jit(DeterministicRng rng, int span) => rng.nextInt(2 * span + 1) - span;

  /// 후보 1개 샘플.
  Candidate sample(DeterministicRng rng) {
    // 다중 플라스크 레벨: 플라스크마다 전용 램프를 배정하는 "커버올" 모드를 자주 쓴다.
    // 무작위 sink 배정으로는 {좌 램프+우 램프} 조합 확률이 낮아 해를 못 찾는다(텐트형 해).
    if (sinkX.length > 1 && rng.nextDouble() < 0.55) {
      final k = sinkX.length > cfg.maxStrokes ? cfg.maxStrokes : sinkX.length;
      final strokes = <StrokePrimitive>[
        for (var i = 0; i < k; i++)
          _directedTo(rng, inks[rng.nextInt(inks.length)], i),
      ];
      return Candidate(strokes, gravityTaps: _sampleTaps(rng));
    }
    final k = _sampleK(rng);
    final strokes = <StrokePrimitive>[
      for (var i = 0; i < k; i++) _sampleStroke(rng),
    ];
    return Candidate(strokes, gravityTaps: _sampleTaps(rng));
  }

  int _sampleK(DeterministicRng rng) {
    final r = rng.nextDouble();
    // 1~2선분에 무게, maxStrokes까지 꼬리.
    if (r < 0.38) return 1;
    if (r < 0.72) return _min2();
    if (r < 0.90) return _clampK(3);
    return _clampK(cfg.maxStrokes);
  }

  int _min2() => cfg.maxStrokes >= 2 ? 2 : 1;
  int _clampK(int k) => k > cfg.maxStrokes ? cfg.maxStrokes : k;

  StrokePrimitive _sampleStroke(DeterministicRng rng) {
    final ink = inks[rng.nextInt(inks.length)];
    final mode = rng.nextDouble();
    if (mode < 0.60) return _directed(rng, ink);
    if (mode < 0.85) return _free(rng, ink);
    return _deflector(rng, ink);
  }

  /// 방향 램프(무작위 싱크). 깔때기 프라이어.
  StrokePrimitive _directed(DeterministicRng rng, InkType ink) =>
      _directedTo(rng, ink, rng.nextInt(sinkX.length));

  /// [sinkIdx]번 플라스크로 향하는 방향 램프 (커버올 모드가 플라스크별로 호출).
  ///
  /// 시작점: 소스 열 근처 + 낙하/상승 흐름을 잡는 상단~중단 y. 끝점: 플라스크 중심 ±섭동.
  /// y-스팬을 넓게 잡아 하단 플라스크(내려가는 램프)와 상단 플라스크(중력 반전 시 올라가는
  /// 램프, 예 L011)를 대칭적으로 만든다 — 상단 플라스크를 상단에 붙여 뭉개지 않는다.
  StrokePrimitive _directedTo(DeterministicRng rng, InkType ink, int sinkIdx) {
    final src = srcX[rng.nextInt(srcX.length)];
    final si = sinkIdx % sinkX.length;
    final sink = sinkX[si];
    final cy = sinkCy[si];
    final midY = (yLo + yHi) ~/ 2; // 흐름을 잡는 상단~중단 밴드 상한.
    final sx = _snap(src + _jit(rng, 24), xLo, xHi);
    final sy = _snap(_rand(rng, yLo, midY < yLo ? yLo : midY), 0, _h - 1);
    final ex = _snap(sink + _jit(rng, 24), xLo, xHi);
    final ey = _snap(cy + _jit(rng, 30), 0, _h - 1);
    return StrokePrimitive(ink, sx, sy, ex, ey);
  }

  /// 자유 선분: 바운딩 박스 내 무작위 (지형 우회·예외 케이스 커버).
  StrokePrimitive _free(DeterministicRng rng, InkType ink) {
    final sx = _snap(_rand(rng, xLo, xHi), xLo, xHi);
    final sy = _snap(_rand(rng, yLo, yHi), 0, _h - 1);
    final ex = _snap(_rand(rng, xLo, xHi), xLo, xHi);
    final ey = _snap(_rand(rng, yLo, yHi), 0, _h - 1);
    return StrokePrimitive(ink, sx, sy, ex, ey);
  }

  /// 짧은 편향판: 중간 지점 근처의 짧은 선분 (정밀 보정·미세 유도).
  StrokePrimitive _deflector(DeterministicRng rng, InkType ink) {
    final cx = _rand(rng, xLo, xHi);
    final cy = _rand(rng, yLo, yHi);
    final len = cfg.snap * _rand(rng, 1, 4);
    final dx = _jit(rng, len);
    final dy = _jit(rng, len);
    final sx = _snap(cx - dx ~/ 2, xLo, xHi);
    final sy = _snap(cy - dy ~/ 2, 0, _h - 1);
    final ex = _snap(cx + dx ~/ 2, xLo, xHi);
    final ey = _snap(cy + dy ~/ 2, 0, _h - 1);
    return StrokePrimitive(ink, sx, sy, ex, ey);
  }

  List<int> _sampleTaps(DeterministicRng rng) {
    if (!hasGravity) return const [];
    final r = rng.nextDouble();
    if (r < 0.45) return const [];
    if (r < 0.85) return [_tapTicks[rng.nextInt(_tapTicks.length)]];
    return [
      _tapTicks[rng.nextInt(_tapTicks.length)],
      _tapTicks[rng.nextInt(_tapTicks.length)],
    ];
  }

  /// 국소 정련용 변이: 좌표 섭동 / 선분 축소 / 선분 제거 / 중력 탭 조정.
  Candidate mutate(Candidate c, DeterministicRng rng) {
    final strokes = [...c.strokes];
    final taps = [...c.gravityTaps];
    final opCount = hasGravity ? 5 : 4;
    final op = rng.nextInt(opCount);

    switch (op) {
      case 0:
      case 1:
        // 한 선분의 한 끝점을 ±d 섭동.
        if (strokes.isNotEmpty) {
          final i = rng.nextInt(strokes.length);
          final d = [cfg.snap, cfg.snap ~/ 2, 2][rng.nextInt(3)];
          final s = strokes[i];
          final movEnd = rng.nextBool();
          final ddx = _jit(rng, d);
          final ddy = _jit(rng, d);
          strokes[i] = movEnd
              ? s.copyWith(
                  x1: _clampX(s.x1 + ddx), y1: _clampY(s.y1 + ddy))
              : s.copyWith(
                  x0: _clampX(s.x0 + ddx), y0: _clampY(s.y0 + ddy));
        }
      case 2:
        // 선분 축소 (양 끝점을 중점으로 당겨 잉크 절약).
        if (strokes.isNotEmpty) {
          final i = rng.nextInt(strokes.length);
          final s = strokes[i];
          final mx = (s.x0 + s.x1) ~/ 2;
          final my = (s.y0 + s.y1) ~/ 2;
          final t = cfg.snap ~/ 2;
          strokes[i] = StrokePrimitive(
            s.ink,
            _clampX(s.x0 + (mx - s.x0).sign * t),
            _clampY(s.y0 + (my - s.y0).sign * t),
            _clampX(s.x1 + (mx - s.x1).sign * t),
            _clampY(s.y1 + (my - s.y1).sign * t),
          );
        }
      case 3:
        // 선분 제거 (2개 이상일 때).
        if (strokes.length > 1) {
          strokes.removeAt(rng.nextInt(strokes.length));
        }
      case 4:
        // 중력 탭 조정: 추가/제거/이동.
        if (taps.isEmpty) {
          taps.add(_tapTicks[rng.nextInt(_tapTicks.length)]);
        } else {
          final j = rng.nextInt(taps.length);
          if (rng.nextBool()) {
            taps.removeAt(j);
          } else {
            taps[j] = (taps[j] + _jit(rng, 40)).clamp(0, cfg.tickCap - 1);
          }
        }
    }
    return Candidate(strokes, gravityTaps: taps);
  }
}
