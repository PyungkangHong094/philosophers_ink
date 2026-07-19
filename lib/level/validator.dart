/// 레벨 의미 검증기 (GDD 10.6). 스키마 필수/좌표/물질/해금 정합성을 검사하고
/// 위반이 하나라도 있으면 [LevelException]으로 **전부 모아** 던진다 (조용한 스킵 금지).
///
/// 순수 Dart. 그리드 치수는 sim의 상수(공개)를 신뢰한다.
library;

import '../core/constants.dart';
import '../sim/materials.dart';
import 'level_exception.dart';
import 'level_model.dart';

/// 스키마 범위 (LEVELS.md 7장). 매직 넘버 금지 — 범위 동기화의 단일 소스.
const int kMinChapter = 1;
const int kMaxChapter = 4;
const int kMinDifficulty = 1;
const int kMaxDifficulty = 10;

/// 요소별 최소 해금 챕터 (GDD 7.1 / LEVELS.md 1장).
/// 레벨 챕터가 이 값보다 작으면 "아직 해금 안 된 요소" 위반.
const Map<Material, int> _materialUnlockChapter = {
  Material.prima: 1,
  Material.wall: 1,
  Material.coldLine: 2,
  Material.ice: 2,
  Material.water: 2,
  Material.heatLine: 3,
  Material.steam: 3,
  Material.ash: 3,
  Material.lava: 4,
  Material.stone: 4,
};

const Map<InkType, int> _inkUnlockChapter = {
  InkType.chalk: 1,
  InkType.frost: 2,
  InkType.heat: 3,
};

const Map<String, int> _gimmickUnlockChapter = {
  GimmickType.gravityFlip: 1,
  GimmickType.tempZone: 2,
  GimmickType.portal: 2,
  GimmickType.varianceGate: 2,
  GimmickType.ashEmitter: 3,
};

/// 상태 플라스크(챕터2)·순수(챕터3)·유한 방출(챕터3) 해금 챕터.
const int _stateFlaskChapter = 2;
const int _pureFlaskChapter = 3;
const int _finiteEmitChapter = 3;
const int _ashEmitChapter = 3;

/// 레벨을 검증한다. 통과하면 무반환, 실패하면 [LevelException]을 던진다.
void validateLevel(Level level, {String source = 'level'}) {
  final problems = <String>[];
  final w = SimConstants.gridWidth;
  final h = SimConstants.gridHeight;
  final chapter = level.meta.chapter;

  // --- meta ---
  if (level.meta.id <= 0) problems.add('meta.id는 양수여야 한다 (got ${level.meta.id})');
  if (chapter < kMinChapter || chapter > kMaxChapter) {
    problems.add('meta.chapter는 $kMinChapter~$kMaxChapter여야 한다 (got $chapter)');
  }
  if (level.meta.difficulty < kMinDifficulty ||
      level.meta.difficulty > kMaxDifficulty) {
    problems.add(
        'meta.difficulty는 $kMinDifficulty~$kMaxDifficulty이어야 한다 (got ${level.meta.difficulty})');
  }
  if (level.meta.optimalInk != null) {
    level.meta.optimalInk!.forEach((ink, v) {
      if (v < 0) problems.add('meta.optimal_ink.${ink.name}은 음수일 수 없다 (got $v)');
    });
  }
  if (level.timeLimitSeconds != null && level.timeLimitSeconds! <= 0) {
    problems.add('time_limit_s는 양수여야 한다 (got ${level.timeLimitSeconds})');
  }
  // 힌트 스트로크(GDD 12장): 있으면 비어있지 않아야 하고, 각 선분 끝점이 그리드 안,
  // 잉크 종류가 이 챕터에서 해금돼 있어야 한다(힌트가 미해금 잉크를 보이면 거짓말).
  final hints = level.meta.hintStroke;
  if (hints != null) {
    if (hints.isEmpty) {
      problems.add('meta.hint_stroke가 빈 배열 — 힌트 없음은 null이어야 한다');
    }
    for (var i = 0; i < hints.length; i++) {
      final s = hints[i];
      final tag = 'meta.hint_stroke[$i]';
      for (final (name, px, py) in [
        ('시작', s.x0, s.y0),
        ('끝', s.x1, s.y1),
      ]) {
        if (px < 0 || px >= w || py < 0 || py >= h) {
          problems.add('$tag $name점($px,$py)이 그리드(${w}x$h) 밖');
        }
      }
      final unlock = _inkUnlockChapter[s.ink]!;
      if (chapter < unlock) {
        problems.add('$tag 잉크 ${s.ink.name}은 챕터 $unlock부터 해금 (레벨 챕터 $chapter)');
      }
    }
  }

  // --- 방출구 ---
  if (level.emitters.isEmpty) {
    problems.add('emitters가 비어 있다 — 방출구가 최소 1개 필요');
  }
  for (var i = 0; i < level.emitters.length; i++) {
    final e = level.emitters[i];
    final tag = 'emitters[$i]';
    if (e.width < 1) problems.add('$tag width는 1 이상이어야 한다 (got ${e.width})');
    if (e.x < 0 || e.y < 0 || e.x + e.width > w || e.y >= h) {
      problems.add('$tag 밴드(${e.x},${e.y} w${e.width})가 그리드(${w}x$h) 밖');
    }
    if (e.rate < 1) {
      problems.add('$tag rate(방출 간격)는 1 이상이어야 한다 (got ${e.rate})');
    }
    final cat = categoryOf(e.material.index);
    if (cat == MaterialCategory.none || cat == MaterialCategory.staticSolid) {
      problems.add('$tag 물질 ${materialName(e.material)}은 방출 불가(정적/빈칸)');
    }
    _checkMaterialUnlock(problems, tag, e.material, chapter);
    if (e.ashRatio < 0 || e.ashRatio > 1) {
      problems.add('$tag ash_ratio는 0~1 (got ${e.ashRatio})');
    }
    if (e.ashRatio > 0 && chapter < _ashEmitChapter) {
      problems.add('$tag 재 방출구(ash_ratio>0)는 챕터 $_ashEmitChapter부터 (레벨 챕터 $chapter)');
    }
    if (e.total != null) {
      if (e.total! < 0) problems.add('$tag total은 음수일 수 없다 (got ${e.total})');
      if (chapter < _finiteEmitChapter) {
        problems.add('$tag 유한 방출(total)은 챕터 $_finiteEmitChapter부터 (레벨 챕터 $chapter)');
      }
    }
  }

  // --- 플라스크 ---
  if (level.flasks.isEmpty) {
    problems.add('flasks가 비어 있다 — 목표 플라스크가 최소 1개 필요');
  }
  for (var i = 0; i < level.flasks.length; i++) {
    final f = level.flasks[i];
    final tag = 'flasks[$i]';
    // 개방형 비커(GDD 5.1 입구 규칙): 좌·우 벽 + 내부 + 바닥 벽이 필요하므로
    // 폭 ≥3(좌벽·내부·우벽), 높이 ≥2(내부·바닥벽)여야 내부 판정 영역이 생긴다.
    if (f.w < 3 || f.h < 2) {
      problems.add('$tag 크기(${f.w}x${f.h})는 최소 3x2 (개방형 비커 내부 확보)');
    }
    if (f.x < 0 || f.y < 0 || f.x + f.w > w || f.y + f.h > h) {
      problems.add('$tag 영역(${f.x},${f.y} ${f.w}x${f.h})이 그리드(${w}x$h) 밖');
    }
    if (f.goal <= 0) problems.add('$tag goal은 양수여야 한다 (got ${f.goal})');
    if (f.material != null) {
      _checkMaterialUnlock(problems, tag, f.material!, chapter);
    }
    if (f.state != null && chapter < _stateFlaskChapter) {
      problems.add('$tag 상태 플라스크는 챕터 $_stateFlaskChapter부터 (레벨 챕터 $chapter)');
    }
    if (f.pure && chapter < _pureFlaskChapter) {
      problems.add('$tag 순수(❗) 플라스크는 챕터 $_pureFlaskChapter부터 (레벨 챕터 $chapter)');
    }
  }

  // --- 지형 ---
  for (var i = 0; i < level.terrain.length; i++) {
    final t = level.terrain[i];
    final tag = 'terrain[$i]';
    if (t.w < 1 || t.h < 1) {
      problems.add('$tag 크기(${t.w}x${t.h})는 1 이상이어야 한다');
    }
    if (t.x < 0 || t.y < 0 || t.x + t.w > w || t.y + t.h > h) {
      problems.add('$tag 영역이 그리드(${w}x$h) 밖');
    }
    _checkMaterialUnlock(problems, tag, t.material, chapter);
  }

  // --- 잉크 예산 (해금 정합성) ---
  level.inkBudget.forEach((ink, budget) {
    if (budget < 0) {
      problems.add('ink_budget.${ink.name}은 음수일 수 없다 (got $budget)');
    }
    final unlock = _inkUnlockChapter[ink]!;
    if (budget > 0 && chapter < unlock) {
      problems.add('${ink.name} 잉크는 챕터 $unlock부터 해금 — 레벨 챕터 $chapter에서 예산 지급 불가');
    }
  });

  // --- 기믹 (GDD 6장): 해금 정합 + type별 파라미터 의미 검증 ---
  for (var i = 0; i < level.gimmicks.length; i++) {
    _validateGimmick(problems, level.gimmicks[i], 'gimmicks[$i]', chapter, w, h);
  }

  if (problems.isNotEmpty) {
    throw LevelException(problems, source: source);
  }
}

/// 기믹 1개의 해금 정합성 + type별 파라미터를 검증한다.
void _validateGimmick(
  List<String> problems,
  GimmickSpec g,
  String tag,
  int chapter,
  int gridW,
  int gridH,
) {
  final unlock = _gimmickUnlockChapter[g.type];
  if (unlock == null) {
    problems.add('$tag 알 수 없는 기믹 type "${g.type}"');
    return; // type을 모르면 파라미터 검증 불가.
  }
  if (chapter < unlock) {
    problems.add('$tag 기믹 "${g.type}"은 챕터 $unlock부터 (레벨 챕터 $chapter)');
  }
  final p = g.params;
  switch (g.type) {
    case GimmickType.varianceGate:
      _checkRect(problems, tag, p, gridW, gridH);
      final to = _checkGimmickMaterial(
          problems, '$tag.${GimmickParamKey.to}', p[GimmickParamKey.to], chapter,
          required: true);
      if (to != null && !_isMobileMaterial(to)) {
        problems.add('$tag.${GimmickParamKey.to} 변환 결과는 이동 물질이어야 한다 (got ${materialName(to)})');
      }
      if (p[GimmickParamKey.from] != null) {
        _checkGimmickMaterial(problems, '$tag.${GimmickParamKey.from}',
            p[GimmickParamKey.from], chapter,
            required: false);
      }
    case GimmickType.portal:
      final entryCells =
          _checkRectField(problems, '$tag.${GimmickParamKey.entry}',
              p[GimmickParamKey.entry], gridW, gridH);
      final exitCells = _checkRectField(problems,
          '$tag.${GimmickParamKey.exit}', p[GimmickParamKey.exit], gridW, gridH);
      if (entryCells != null && exitCells != null && entryCells != exitCells) {
        problems.add(
            '$tag 포탈 입구($entryCells셀)·출구($exitCells셀) 셀 수가 같아야 한다 (1:1 매핑)');
      }
    case GimmickType.tempZone:
      _checkRect(problems, tag, p, gridW, gridH);
      final kind = p[GimmickParamKey.kind];
      if (kind != kTempZoneHeat && kind != kTempZoneCool) {
        problems.add(
            '$tag.${GimmickParamKey.kind}는 "$kTempZoneHeat" 또는 "$kTempZoneCool" (got $kind)');
      }
      final prob = p[GimmickParamKey.probability];
      if (prob != null) {
        if (prob is! num) {
          problems.add('$tag.${GimmickParamKey.probability}는 숫자여야 한다 (got $prob)');
        } else if (prob < 0 || prob > 1) {
          problems.add('$tag.${GimmickParamKey.probability}는 0~1 (got $prob)');
        }
      }
    case GimmickType.gravityFlip:
    case GimmickType.ashEmitter:
      // 존/좌표 없음 — 파라미터 검증 불필요(마커).
      break;
  }
}

/// params에서 직사각형(x,y,w,h)을 검증한다. 셀 수를 반환(무효면 null).
int? _checkRect(
  List<String> problems,
  String tag,
  Map<String, dynamic> p,
  int gridW,
  int gridH,
) {
  final x = p[GimmickParamKey.x];
  final y = p[GimmickParamKey.y];
  final ww = p[GimmickParamKey.w];
  final hh = p[GimmickParamKey.h];
  if (x is! int || y is! int || ww is! int || hh is! int) {
    problems.add('$tag 존 좌표(x,y,w,h)는 정수여야 한다');
    return null;
  }
  var ok = true;
  if (ww < 1 || hh < 1) {
    problems.add('$tag 존 크기(${ww}x$hh)는 1 이상이어야 한다');
    ok = false;
  }
  if (x < 0 || y < 0 || x + ww > gridW || y + hh > gridH) {
    problems.add('$tag 존($x,$y ${ww}x$hh)이 그리드(${gridW}x$gridH) 밖');
    ok = false;
  }
  return ok ? ww * hh : null;
}

/// 중첩 rect 객체({x,y,w,h}) 필드를 검증한다. 셀 수 반환(무효면 null).
int? _checkRectField(
  List<String> problems,
  String tag,
  dynamic v,
  int gridW,
  int gridH,
) {
  if (v is! Map) {
    problems.add('$tag rect 객체(x,y,w,h)가 필요 (got ${v.runtimeType})');
    return null;
  }
  return _checkRect(problems, tag, v.cast<String, dynamic>(), gridW, gridH);
}

/// 기믹 파라미터의 물질명을 검증한다(해금 포함). 유효하면 Material 반환.
Material? _checkGimmickMaterial(
  List<String> problems,
  String tag,
  dynamic v,
  int chapter, {
  required bool required,
}) {
  if (v == null) {
    if (required) problems.add('$tag 물질명이 필요하다');
    return null;
  }
  if (v is! String) {
    problems.add('$tag 물질명은 문자열이어야 한다 (got $v)');
    return null;
  }
  final m = materialFromName(v);
  if (m == null) {
    problems.add('$tag 알 수 없는 물질 "$v"');
    return null;
  }
  _checkMaterialUnlock(problems, tag, m, chapter);
  return m;
}

/// 이동 물질(입자/액체/기체)인가 — 변성 게이트 결과 물질 제약용.
bool _isMobileMaterial(Material m) {
  final cat = categoryOf(m.index);
  return cat == MaterialCategory.particle ||
      cat == MaterialCategory.liquid ||
      cat == MaterialCategory.gas;
}

void _checkMaterialUnlock(
  List<String> problems,
  String tag,
  Material material,
  int chapter,
) {
  final unlock = _materialUnlockChapter[material];
  if (unlock == null) {
    problems.add('$tag 물질 ${materialName(material)}은 레벨에 배치할 수 없다');
    return;
  }
  if (chapter < unlock) {
    problems.add(
      '$tag 물질 ${materialName(material)}은 챕터 $unlock부터 해금 (레벨 챕터 $chapter)',
    );
  }
}
