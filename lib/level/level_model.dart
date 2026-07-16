/// 레벨 데이터 모델 (GDD 10.6 + LEVELS.md 7장). 순수 Dart — flutter 미의존.
///
/// JSON 스키마의 인메모리 표현. 구조적 파싱은 [loader], 의미 검증은 [validator]가 맡고,
/// 이 파일은 형(型)과 파생 유틸(물질명 매핑·상 매핑)만 정의한다.
library;

import '../sim/materials.dart';

export '../sim/materials.dart' show InkType, Material;

/// 플라스크 상태 조건 (GDD 5.1). 착수 시점의 상(고/액/기)에 매핑한다.
enum FlaskState { solid, liquid, gas }

extension FlaskStateX on FlaskState {
  String get key => switch (this) {
        FlaskState.solid => 'solid',
        FlaskState.liquid => 'liquid',
        FlaskState.gas => 'gas',
      };
}

/// 문자열 → 상태. 알 수 없으면 null.
FlaskState? flaskStateFromKey(String key) => switch (key) {
      'solid' => FlaskState.solid,
      'liquid' => FlaskState.liquid,
      'gas' => FlaskState.gas,
      _ => null,
    };

/// 물질 카테고리 → 착수 상. 정적(none/staticSolid)은 착수 상이 아니라 null.
/// 입자=고체, 액체=액체, 기체=기체 (GDD 3.3 카테고리를 상으로 사상).
FlaskState? flaskStateForCategory(MaterialCategory c) => switch (c) {
      MaterialCategory.particle => FlaskState.solid,
      MaterialCategory.liquid => FlaskState.liquid,
      MaterialCategory.gas => FlaskState.gas,
      MaterialCategory.none => null,
      MaterialCategory.staticSolid => null,
    };

/// 물질 이름(JSON 표기, 예 "WATER") → Material. 알 수 없으면 null.
/// kMaterialTable의 name을 단일 소스로 역인덱싱한다.
final Map<String, Material> _materialByName = {
  for (final props in kMaterialTable) props.name: props.id,
};

Material? materialFromName(String name) => _materialByName[name];

/// Material → JSON 이름 (에디터 익스포트 라운드트립용).
String materialName(Material m) => kMaterialTable[m.index].name;

/// meta 블록 (LEVELS.md 7장).
class LevelMeta {
  final int id;
  final String name;
  final int chapter;
  final int difficulty;

  /// 이 레벨이 처음 가르치는 새 요소 키 (교육 레벨만 비어있지 않음).
  final List<String> teaches;
  final List<String> tags;

  /// 최적해 잉크(셀 수). null이면 미검증 — 별점은 ★만 부여 (LEVELS 4장).
  final Map<InkType, int>? optimalInk;

  /// 검증된 상이한 해법 수 (LEVELS 3장 원칙: 최소 2).
  final int solutionsVerified;

  /// 힌트용 정답 스트로크 좌표열. 작업 레벨은 null (LEVELS 7장).
  final List<List<int>>? hintStroke;

  const LevelMeta({
    required this.id,
    required this.name,
    required this.chapter,
    required this.difficulty,
    this.teaches = const [],
    this.tags = const [],
    this.optimalInk,
    this.solutionsVerified = 0,
    this.hintStroke,
  });

  /// 최적해 총량(셀 수 합). optimalInk 없으면 null.
  int? get optimalTotal {
    final o = optimalInk;
    if (o == null) return null;
    return o.values.fold<int>(0, (a, b) => a + b);
  }
}

/// 방출구 (GDD 10.6). sim의 EmitterConfig로 매핑되는 방출 스펙.
class EmitterSpec {
  final int x;
  final int y;

  /// 방출 밴드 폭(셀). 점 방출구=1, 넓은 레토르트 목=여러 칸.
  final int width;
  final Material material;

  /// 방출 간격 — N틱마다 1회 (sim intervalTicks). 1 이상. 클수록 느리다.
  final num rate;

  /// 총 방출량. null이면 무한 방출 (GDD 5.2).
  final int? total;

  /// 재 혼합 비율 0~1 (재 방출구, GDD 6장). 0이면 순수 방출.
  final double ashRatio;

  const EmitterSpec({
    required this.x,
    required this.y,
    required this.material,
    required this.rate,
    this.width = 1,
    this.total,
    this.ashRatio = 0.0,
  });
}

/// 플라스크 (GDD 5.1). 요구 조건의 정적 정의 — 런타임 카운트는 gameplay/flask.dart.
class FlaskSpec {
  final int x;
  final int y;
  final int w;
  final int h;

  /// 목표 개수 (착수 카운트).
  final int goal;

  /// 물질 지정 조건. null이면 물질 무관.
  final Material? material;

  /// 상태 지정 조건. null이면 상 무관.
  final FlaskState? state;

  /// 순수(❗) — ASH 1개라도 혼입 시 실패 (GDD 5.1).
  final bool pure;

  const FlaskSpec({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.goal,
    this.material,
    this.state,
    this.pure = false,
  });
}

/// 정적 지형 사각형 (레벨 고정 벽 등). 로드 시 그리드에 스탬프된다.
class TerrainRect {
  final int x;
  final int y;
  final int w;
  final int h;
  final Material material;

  const TerrainRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.material,
  });
}

/// 기믹 (GDD 6장). M3 구현 전까지는 자리만 확보 — type + 파라미터 맵 보존.
class GimmickSpec {
  final String type;
  final Map<String, dynamic> params;

  const GimmickSpec({required this.type, this.params = const {}});
}

/// 별점 임계 (잉크 사용량 총합 기준). null이면 optimalInk에서 공식 파생 (LEVELS 4장).
class StarThresholds {
  final int twoStar;
  final int threeStar;

  const StarThresholds({required this.twoStar, required this.threeStar});
}

/// 레벨 1개의 완전한 정의.
class Level {
  final LevelMeta meta;

  /// 배경색 0xAARRGGBB.
  final int background;

  final List<EmitterSpec> emitters;
  final List<FlaskSpec> flasks;
  final List<TerrainRect> terrain;
  final List<GimmickSpec> gimmicks;

  /// 잉크 종류당 예산(셀 수). 0인 종류는 병 숨김 (GDD 4.2).
  final Map<InkType, int> inkBudget;

  /// 명시 별점 임계. null이면 meta.optimalInk에서 파생.
  final StarThresholds? starThresholds;

  const Level({
    required this.meta,
    required this.background,
    required this.emitters,
    required this.flasks,
    this.terrain = const [],
    this.gimmicks = const [],
    required this.inkBudget,
    this.starThresholds,
  });
}
