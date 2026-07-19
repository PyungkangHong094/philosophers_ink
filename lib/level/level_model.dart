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

/// 플라스크 개방부 방향 (GDD 5.1 입구 규칙). up=위 개방(바닥 부착, 기본),
/// down=아래 개방(천장 부착 — 중력 반전 레벨에서 상승 물질을 받는다, 비주얼 ∩자).
enum FlaskMouth { up, down }

extension FlaskMouthX on FlaskMouth {
  String get key => this == FlaskMouth.up ? 'up' : 'down';
}

/// 문자열 → 개방부 방향. 알 수 없으면 null.
FlaskMouth? flaskMouthFromKey(String key) => switch (key) {
      'up' => FlaskMouth.up,
      'down' => FlaskMouth.down,
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

  /// 개방부 방향 (GDD 5.1). up=위 개방(기본), down=아래 개방(천장 부착). 벽 3면은 물리 벽.
  final FlaskMouth mouth;

  const FlaskSpec({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.goal,
    this.material,
    this.state,
    this.pure = false,
    this.mouth = FlaskMouth.up,
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

/// 기믹 (GDD 6장). 저장·직렬화는 type + 파라미터 맵의 제네릭 형으로 유지한다
/// (왕복 무손실·에디터 무수정). 파라미터 의미 검증은 [validator], sim 인스턴스
/// 변환은 [buildGimmicks](gimmick_builder.dart)가 [GimmickType]/[GimmickParamKey]로
/// 수행한다 — 매직 스트링 단일 소스.
class GimmickSpec {
  final String type;
  final Map<String, dynamic> params;

  const GimmickSpec({required this.type, this.params = const {}});
}

/// 기믹 type 식별자 (JSON `type` 필드). GDD 6장 5종.
/// - [varianceGate] 변성 게이트: 존 통과 물질을 [GimmickParamKey.to]로 변환.
/// - [gravityFlip] 중력 반전 버튼: 존 없음 — 존재만으로 게임플레이 버튼 활성.
/// - [portal] 포탈: [GimmickParamKey.entry]→[GimmickParamKey.exit] 순간이동(일방향).
/// - [tempZone] 온도 존: 레벨 고정 화로/빙결 지대(잉크 룬 없이 상전이).
/// - [ashEmitter] 재 방출구: 실제 거동은 방출구 `ash_ratio`가 담당하는 마커 태그.
abstract final class GimmickType {
  static const String varianceGate = 'variance_gate';
  static const String gravityFlip = 'gravity_flip';
  static const String portal = 'portal';
  static const String tempZone = 'temp_zone';
  static const String ashEmitter = 'ash_emitter';

  /// 인식되는 모든 기믹 type.
  static const Set<String> all = {
    varianceGate,
    gravityFlip,
    portal,
    tempZone,
    ashEmitter,
  };
}

/// 기믹 params 맵의 키 이름 (매직 스트링 단일 소스).
abstract final class GimmickParamKey {
  static const String x = 'x';
  static const String y = 'y';
  static const String w = 'w';
  static const String h = 'h';

  /// 변성 게이트: 변환 결과 물질명(필수).
  static const String to = 'to';

  /// 변성 게이트: 변환 대상 물질명(선택 — 없으면 모든 이동 물질).
  static const String from = 'from';

  /// 포탈: 입구 rect 객체 {x,y,w,h}.
  static const String entry = 'entry';

  /// 포탈: 출구 rect 객체 {x,y,w,h}.
  static const String exit = 'exit';

  /// 온도 존: "heat" | "cool".
  static const String kind = 'kind';

  /// 온도 존: ±1단계 전이 확률(0~1). 없거나 null이면 룬 기본 강도.
  static const String probability = 'probability';
}

/// 온도 존 kind JSON 값.
const String kTempZoneHeat = 'heat';
const String kTempZoneCool = 'cool';

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

  /// 제한 시간(초, GDD 2장). null이면 난이도 밴드 기본값을 세션이 적용한다.
  /// 시간은 시뮬 틱 기반(60Hz) — 세션이 초×tickRate로 환산한다.
  final int? timeLimitSeconds;

  const Level({
    required this.meta,
    required this.background,
    required this.emitters,
    required this.flasks,
    this.terrain = const [],
    this.gimmicks = const [],
    required this.inkBudget,
    this.starThresholds,
    this.timeLimitSeconds,
  });
}
