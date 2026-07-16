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
  'gravity_flip': 1,
  'temp_zone': 2,
  'portal': 2,
  'variance_gate': 2,
  'ash_emitter': 3,
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
    if (f.w < 1 || f.h < 1) {
      problems.add('$tag 크기(${f.w}x${f.h})는 1 이상이어야 한다');
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

  // --- 기믹 (M3 전이지만 자리 확보 + 해금 정합) ---
  for (var i = 0; i < level.gimmicks.length; i++) {
    final g = level.gimmicks[i];
    final tag = 'gimmicks[$i]';
    final unlock = _gimmickUnlockChapter[g.type];
    if (unlock == null) {
      problems.add('$tag 알 수 없는 기믹 type "${g.type}"');
    } else if (chapter < unlock) {
      problems.add('$tag 기믹 "${g.type}"은 챕터 $unlock부터 (레벨 챕터 $chapter)');
    }
  }

  if (problems.isNotEmpty) {
    throw LevelException(problems, source: source);
  }
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
