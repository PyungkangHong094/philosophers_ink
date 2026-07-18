/// 물질 ID와 속성 중앙 테이블 (GDD 3.1).
///
/// 순수 Dart. flutter/dart:ui import 금지 — 색은 0xAARRGGBB 정수로만 들고,
/// 렌더 시점의 RGBA 룩업 버퍼 생성은 render/palette.dart가 담당한다.
///
/// 물질을 추가할 때 고쳐야 하는 곳은 이 파일의 [kMaterialTable] 한 곳뿐이다.
/// 카테고리별 이동/전이 처리에서 switch문을 산개시키지 않는다 (스킬 규칙).
///
/// core/constants.dart(순수 Dart)만 import한다 — 확산 밸런스 값의 단일 소스.
library;

import '../core/constants.dart';

/// 카테고리별 이동 규칙의 분류 (GDD 3.3).
enum MaterialCategory {
  /// 이동 없음 (EMPTY 포함, WALL/룬 선).
  none,

  /// 정적 고체 — 벽·룬 선. 이동 없음.
  staticSolid,

  /// 입자 — 아래 → 아래대각.
  particle,

  /// 액체 — 아래 → 아래대각 → 수평 확산.
  liquid,

  /// 기체 — 위 → 위대각 → 수평 (액체의 상하 미러).
  gas,
}

/// 물질 ID. enum 인덱스가 곧 그리드 셀에 저장되는 1바이트 ID다.
/// **순서 고정** (GDD 3.1 테이블): EMPTY=0 … STONE=10.
enum Material {
  empty, // 0
  wall, // 1
  heatLine, // 2
  coldLine, // 3
  prima, // 4
  ice, // 5
  water, // 6
  steam, // 7
  ash, // 8
  lava, // 9
  stone, // 10
}

/// 물질 하나의 속성. 카테고리 + 가열/냉각 전이 대상 + 확산 거동 + 팔레트 색.
class MaterialProps {
  final Material id;
  final String name;
  final MaterialCategory category;

  /// 가열 시 전이 대상. null이면 불변.
  final Material? heatTo;

  /// 냉각 시 전이 대상. null이면 불변.
  final Material? coolTo;

  /// 한 틱 수평 확산 최대 셀 수 (액체/기체). 입자·정적은 0.
  /// 실제 밸런스 값은 constants에서 온다 — 테이블은 어떤 상수를 쓸지만 배선한다.
  final int dispersion;

  /// 입자가 낮은 안식각으로 옆으로 미끄러지는가 (ICE 전용 구조 플래그).
  /// 미끄러짐 확률 값은 SimConstants.iceSlipChance.
  final bool granularSlip;

  /// 팔레트 색 0xAARRGGBB. render/palette.dart가 RGBA LUT로 변환한다.
  final int argb;

  const MaterialProps({
    required this.id,
    required this.name,
    required this.category,
    required this.heatTo,
    required this.coolTo,
    required this.argb,
    this.dispersion = 0,
    this.granularSlip = false,
  });
}

/// 잉크 3종 (GDD 4.1). 스트로크가 배치하는 물질과 1:1 대응.
/// gameplay-engineer의 잉크 예산이 이 타입 위에서 차감한다 (계약).
enum InkType { chalk, heat, frost }

/// 잉크 → 배치 물질. chalk=석필(WALL), heat=화염 룬(HEAT_LINE), frost=서리 룬(COLD_LINE).
Material materialForInk(InkType ink) => switch (ink) {
      InkType.chalk => Material.wall,
      InkType.heat => Material.heatLine,
      InkType.frost => Material.coldLine,
    };

/// 중앙 물질 테이블. 인덱스 == Material.index == 셀 ID.
///
/// 색 근거 (GDD 8.2): 챕터 1 배경 #1D1418 위에서 물질 간 명도 차 20% 이상.
/// M0에서 실사용하는 것은 EMPTY/WALL/PRIMA뿐이나 테이블 구조는 전체를 잡는다.
const List<MaterialProps> kMaterialTable = [
  MaterialProps(
    id: Material.empty,
    name: 'EMPTY',
    category: MaterialCategory.none,
    heatTo: null,
    coolTo: null,
    // EMPTY = 챕터 1 배경색. 버퍼 자체가 배경을 칠한다.
    argb: 0xFF1D1418,
  ),
  MaterialProps(
    id: Material.wall,
    name: 'WALL',
    category: MaterialCategory.staticSolid,
    heatTo: null,
    coolTo: null,
    // 석필: 배경 대비 밝은 양피지 톤.
    argb: 0xFFCDBFA0,
  ),
  MaterialProps(
    id: Material.heatLine,
    name: 'HEAT_LINE',
    category: MaterialCategory.staticSolid,
    heatTo: null,
    coolTo: null,
    argb: 0xFFE0603C, // 주홍
  ),
  MaterialProps(
    id: Material.coldLine,
    name: 'COLD_LINE',
    category: MaterialCategory.staticSolid,
    heatTo: null,
    coolTo: null,
    argb: 0xFFBFE3F2, // 청백
  ),
  MaterialProps(
    id: Material.prima,
    name: 'PRIMA',
    category: MaterialCategory.particle,
    heatTo: null, // 불활성 — 불변
    coolTo: null,
    argb: 0xFFB79A6A, // 제1질료: 온화한 황토, 배경 대비 명도 확보
  ),
  MaterialProps(
    id: Material.ice,
    name: 'ICE',
    category: MaterialCategory.particle,
    heatTo: Material.water,
    coolTo: null,
    granularSlip: true, // 안식각 낮음 — 잘 퍼진다 (GDD 3.1)
    argb: 0xFF9CD2EA, // 물보다 밝고 채도 낮은 청백 — 물과 명도로 구분
  ),
  MaterialProps(
    id: Material.water,
    name: 'WATER',
    category: MaterialCategory.liquid,
    heatTo: Material.steam,
    coolTo: Material.ice,
    dispersion: SimConstants.liquidDispersion,
    argb: 0xFF3F7BD6,
  ),
  MaterialProps(
    id: Material.steam,
    name: 'STEAM',
    category: MaterialCategory.gas,
    heatTo: null,
    coolTo: Material.water,
    dispersion: SimConstants.gasDispersion,
    argb: 0xFFE4EEF4, // 가장 밝은 톤 — 상승 물질 가독성
  ),
  MaterialProps(
    id: Material.ash,
    name: 'ASH',
    category: MaterialCategory.particle,
    heatTo: null,
    coolTo: null,
    argb: 0xFF5A5048,
  ),
  MaterialProps(
    id: Material.lava,
    name: 'LAVA',
    category: MaterialCategory.liquid,
    heatTo: null,
    coolTo: Material.stone,
    dispersion: SimConstants.liquidDispersion,
    argb: 0xFFE0642A,
  ),
  MaterialProps(
    id: Material.stone,
    name: 'STONE',
    category: MaterialCategory.particle,
    heatTo: null, // 재가열(→LAVA)은 런칭 범위 제외 (GDD 3.1 각주)
    coolTo: null,
    argb: 0xFF6E6A63,
  ),
];

/// 셀 ID → 속성. 핫패스에서 쓰이므로 인덱스 접근.
/// 그리드는 0~10만 기입하나, 손상/미정의 ID가 들어오면 릴리즈에서 RangeError로 크래시한다.
/// assert는 릴리즈에서 제거되어 성능 영향 0 — 디버그에서 원인을 조기에 드러낸다(방어).
MaterialProps propsOf(int id) {
  assert(id >= 0 && id < kMaterialTable.length, '미정의 물질 ID: $id');
  return kMaterialTable[id];
}

/// 셀 ID → 카테고리. rules에서 분기 대신 테이블 조회로 쓴다.
MaterialCategory categoryOf(int id) {
  assert(id >= 0 && id < kMaterialTable.length, '미정의 물질 ID: $id');
  return kMaterialTable[id].category;
}

/// 물질의 상(相) — 상태 플라스크(물방울/눈꽃/김) 판정용 (GDD 5.1).
enum Phase { solid, liquid, gas }

/// 셀 ID → 상. 입자=고체, 액체=액체, 기체=기체. EMPTY·정적(벽/룬선)은 null.
/// "입자는 고체로 카운트"라는 결정을 한 곳에 모은다.
Phase? phaseOf(int id) {
  switch (categoryOf(id)) {
    case MaterialCategory.particle:
      return Phase.solid;
    case MaterialCategory.liquid:
      return Phase.liquid;
    case MaterialCategory.gas:
      return Phase.gas;
    case MaterialCategory.none:
    case MaterialCategory.staticSolid:
      return null;
  }
}
