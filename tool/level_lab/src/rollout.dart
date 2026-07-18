/// 헤드리스 롤아웃 — 해 후보 1개를 심에 주입하고 T틱 돌려 승리 판정 (레벨 랩 L1).
///
/// 스트로크를 t=0에 배치 → 예정된 틱에 중력 버튼 탭 → 매 틱 승리/실패/정체를 검사한다.
/// 결정성: 같은 세션 시드 + 같은 후보 → 같은 결과.
library;

import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/gameplay/headless_session.dart';
import 'package:philosophers_ink/sim/rasterize.dart';

import 'candidate.dart';

/// 롤아웃 1회 결과.
class RolloutResult {
  /// 승리(모든 플라스크 충족)했는가.
  final bool solved;

  /// 배치·차감된 잉크 총량 (승리 시 min_ink 후보).
  final int inkUsed;

  /// 승리/중단까지 진행한 틱 수 (승리 시 클리어 틱).
  final int ticks;

  /// 순수 오염으로 실패했는가 (해가 아님 — 조기 중단).
  final bool contaminated;

  /// 도달한 플라스크 진행 합(목표별 상한 적용). 부분해 적합도(fitness)의 근거 —
  /// 희소 보상 탐색에서 근접해를 향해 언덕오르기하도록 한다.
  final int progress;

  /// 목표 총합(모든 플라스크 goal 합). progress==goalTotal && !contaminated ⇔ solved.
  final int goalTotal;

  const RolloutResult({
    required this.solved,
    required this.inkUsed,
    required this.ticks,
    required this.progress,
    required this.goalTotal,
    this.contaminated = false,
  });

  /// 탐색 적합도: 오염은 강한 페널티, 그 외엔 진행 합.
  int get fitness => contaminated ? -1000000 : progress;
}

/// 롤아웃 예산.
class RolloutConfig {
  /// 틱 상한 (기본 3,600 = 60초분, docs/LEVEL_LAB.md §1). 승리하면 조기 종료.
  final int tickCap;

  /// 플라스크 카운트 합이 이 틱수 동안 오르지 않으면 죽은 배치로 보고 중단 (성능).
  /// 무한 방출구 레벨에서 실패 롤아웃이 tickCap을 다 소모하지 않게 한다.
  final int stallTicks;

  /// 플라스크 영역에 걸치는 스트로크를 무시할지 (기본 true). 플라스크는 영역 내 **모든**
  /// 물질을 카운트하므로, 잉크(WALL/룬 선)를 플라스크 안에 직접 그으면 틱 1에 즉시 클리어되는
  /// 퇴화 해(exploit)가 성립한다. 솔버는 이를 금지해 **정상 해**(물질을 흘려보내는)만 찾는다.
  /// 실제 게임 계약이 아니라 솔버 정책 — HeadlessSession 자체는 게임과 동일하게 카운트한다.
  final bool forbidInFlask;

  const RolloutConfig({
    this.tickCap = 3600,
    this.stallTicks = 500,
    this.forbidInFlask = true,
  });
}

/// [session]에 [cand]를 주입해 롤아웃한다. 세션은 호출자가 재사용(내부에서 reset).
RolloutResult rollout(
  HeadlessSession session,
  Candidate cand,
  RolloutConfig cfg,
) {
  session.reset();

  final goalTotal = _goalTotal(session);

  // 스트로크 배치 (t=0). 잉크 부족분은 부분 배치 cap이 알아서 자른다.
  // forbidInFlask면 플라스크 영역에 걸치는 스트로크는 배치하지 않는다(퇴화 해 차단).
  for (final s in cand.strokes) {
    if (cfg.forbidInFlask && _touchesFlask(session, s.x0, s.y0, s.x1, s.y1)) {
      continue;
    }
    session.applyStroke(s.ink, s.x0, s.y0, s.x1, s.y1);
  }
  final inkUsed = session.inkUsed;

  // 중력 탭: 오름차순 정렬해 해당 틱 직전에 토글.
  final taps = [...cand.gravityTaps]..sort();
  var tapPtr = 0;

  var lastProgress = 0;
  var lastProgressTick = 0;

  for (var t = 0; t < cfg.tickCap; t++) {
    while (tapPtr < taps.length && taps[tapPtr] == t) {
      session.toggleGravity();
      tapPtr++;
    }
    session.tick();

    if (session.isFailed) {
      return RolloutResult(
        solved: false,
        inkUsed: inkUsed,
        ticks: t + 1,
        progress: session.flaskProgress,
        goalTotal: goalTotal,
        contaminated: true,
      );
    }
    if (session.isCleared) {
      return RolloutResult(
        solved: true,
        inkUsed: inkUsed,
        ticks: t + 1,
        progress: goalTotal,
        goalTotal: goalTotal,
      );
    }

    final prog = session.flaskProgress;
    if (prog > lastProgress) {
      lastProgress = prog;
      lastProgressTick = t;
    } else if (t - lastProgressTick >= cfg.stallTicks) {
      // 진행 정체 → 이 배치로는 더 채울 수 없다. 조기 중단.
      break;
    }
  }

  return RolloutResult(
    solved: false,
    inkUsed: inkUsed,
    ticks: cfg.tickCap,
    progress: lastProgress,
    goalTotal: goalTotal,
  );
}

int _goalTotal(HeadlessSession session) {
  var g = 0;
  for (final f in session.flasks.flasks) {
    g += f.spec.goal;
  }
  return g;
}

/// 스트로크(두께 포함)가 어떤 플라스크 사각형이라도 한 셀이라도 건드리는가.
bool _touchesFlask(HeadlessSession session, int x0, int y0, int x1, int y1) {
  final flasks = session.level.flasks;
  if (flasks.isEmpty) return false;
  final cells =
      rasterizeStroke(x0, y0, x1, y1, SimConstants.strokeThicknessCells);
  for (final (x, y) in cells) {
    for (final f in flasks) {
      if (x >= f.x && x < f.x + f.w && y >= f.y && y < f.y + f.h) return true;
    }
  }
  return false;
}
