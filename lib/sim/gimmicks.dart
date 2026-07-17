/// M3 환경 기믹의 시뮬 측 설정 타입 (GDD 6). 순수 Dart.
///
/// 이 파일은 **레벨 데이터(불변)** 만 담는다. 런타임 적용은 [Rules]가 매 틱 수행한다.
/// gameplay-engineer가 레벨 JSON을 파싱해 이 타입들을 [GameState]에 주입한다(계약).
///
/// 좌표계: 셀 (x, y)의 선형 인덱스는 `y * gridWidth + x` (Grid와 동일한 row-major).
/// 팩토리들은 이 규약으로 인덱스를 미리 계산해 둔다 — 핫패스에서 곱셈을 피한다.
library;

import 'materials.dart';

/// 존 안의 물질을 다른 물질로 변환하는 변성 게이트 (GDD 6, 예: PRIMA→WATER).
///
/// 매 틱 [cellIndices]의 각 셀을 검사해, [fromMaterial]과 일치하면 [toMaterial]로
/// 바꾼다. [fromMaterial]이 null이면 **이동 물질(입자/액체/기체) 전부**가 대상이다
/// (정적 벽·룬 선과 EMPTY는 건드리지 않는다). RNG를 쓰지 않아 완전 결정적이다.
///
/// 배치 팁(gameplay): 게이트를 채널 폭 전체에 걸치는 1셀 두께 가로 띠로 두면
/// 수직 이동(입자 1칸/틱)이 게이트를 건너뛰지 못해 확실히 변환된다.
class TransmutationGate {
  /// 게이트가 덮는 셀들의 선형 인덱스(정렬 불필요, 처리 순서는 이 리스트 순서 고정).
  final List<int> cellIndices;

  /// 변환 대상 물질 ID. null이면 모든 이동 물질이 대상.
  final int? fromMaterial;

  /// 변환 결과 물질 ID.
  final int toMaterial;

  const TransmutationGate({
    required this.cellIndices,
    required this.toMaterial,
    this.fromMaterial,
  });

  /// 직사각형 존 [x,y]–[x+width,y+height)를 게이트로 만든다.
  /// [gridWidth]는 인덱스 계산용(그리드 폭). 범위 밖 좌표는 호출자가 보장한다.
  factory TransmutationGate.rect({
    required int gridWidth,
    required int x,
    required int y,
    required int width,
    required int height,
    required int toMaterial,
    int? fromMaterial,
  }) {
    final cells = <int>[];
    for (var yy = y; yy < y + height; yy++) {
      for (var xx = x; xx < x + width; xx++) {
        cells.add(yy * gridWidth + xx);
      }
    }
    return TransmutationGate(
      cellIndices: cells,
      toMaterial: toMaterial,
      fromMaterial: fromMaterial,
    );
  }
}

/// 입구 셀의 물질을 출구 셀로 순간이동시키는 포탈 (GDD 6, 일방향 A→B).
///
/// [entryCells]\[i] → [exitCells]\[i]로 1:1 매핑된다(두 리스트 길이 동일).
/// 이동 물질(입자/액체/기체)만 이동하며, **출구가 막혀 있으면 입구에서 대기**한다
/// (막힘 처리, GDD 6). 양방향이 필요하면 gameplay가 방향을 뒤집은 포탈을 하나 더 둔다.
///
/// 한 틱에 한 번만 이동한다: 이번 틱에 텔레포트로 채워진 셀은 같은 틱에 다시
/// 입구로 소비되지 않는다(이동 스탬프로 보장) — 포탈 연쇄 텔레포트 방지.
class Portal {
  /// 입구 셀 선형 인덱스 목록.
  final List<int> entryCells;

  /// 출구 셀 선형 인덱스 목록. [entryCells]와 길이·순서가 대응한다.
  final List<int> exitCells;

  Portal({required this.entryCells, required this.exitCells})
      : assert(entryCells.length == exitCells.length,
            'entry/exit 셀 수가 같아야 한다 (1:1 매핑)');

  /// 같은 크기의 두 직사각형(입구/출구)을 row-major 순서로 짝지어 포탈을 만든다.
  factory Portal.rects({
    required int gridWidth,
    required int entryX,
    required int entryY,
    required int exitX,
    required int exitY,
    required int width,
    required int height,
  }) {
    final entry = <int>[];
    final exit = <int>[];
    for (var dy = 0; dy < height; dy++) {
      for (var dx = 0; dx < width; dx++) {
        entry.add((entryY + dy) * gridWidth + (entryX + dx));
        exit.add((exitY + dy) * gridWidth + (exitX + dx));
      }
    }
    return Portal(entryCells: entry, exitCells: exit);
  }
}

/// 온도 존의 종류 — 화로(가열) / 빙결 지대(냉각) (GDD 6).
enum TemperatureZoneKind { heat, cool }

/// 레벨 고정 화로/빙결 지대 (GDD 6). 잉크 룬 없이 존 안의 셀을 매 틱 가열/냉각한다.
///
/// M1의 화염·서리 선과 같은 확률적 ±1단계 상전이(GDD 3.3·4.1)를 쓴다. 차이:
/// 룬 선은 인접 4방향으로 복사(radiate)하지만, 온도 존은 **존 안의 셀 자신**에 매 틱
/// 직접 적용한다(존 전체가 온도장). 전이 확률은 존별 [probability]로 재정의할 수 있고,
/// null이면 [Rules]가 SimConstants.pHeat / pCold(룬과 동일 강도)로 해석한다 — 코드에
/// 매직 넘버를 두지 않는다. 전이 불가 물질(벽·EMPTY·불활성)은 RNG를 소비하지 않는다.
class TemperatureZone {
  /// 존이 덮는 셀들의 선형 인덱스.
  final List<int> cellIndices;

  /// 가열/냉각 종류.
  final TemperatureZoneKind kind;

  /// 매 틱 셀당 ±1단계 전이 확률(0~1). null이면 룬과 동일한 기본 강도(pHeat/pCold).
  final double? probability;

  const TemperatureZone({
    required this.cellIndices,
    required this.kind,
    this.probability,
  });

  /// 직사각형 존 [x,y]–[x+width,y+height)를 온도 존으로 만든다.
  factory TemperatureZone.rect({
    required int gridWidth,
    required int x,
    required int y,
    required int width,
    required int height,
    required TemperatureZoneKind kind,
    double? probability,
  }) {
    final cells = <int>[];
    for (var yy = y; yy < y + height; yy++) {
      for (var xx = x; xx < x + width; xx++) {
        cells.add(yy * gridWidth + xx);
      }
    }
    return TemperatureZone(
      cellIndices: cells,
      kind: kind,
      probability: probability,
    );
  }
}

/// 셀 ID가 포탈로 이동 가능한 물질(입자/액체/기체)인지. 게이트·포탈이 공유.
bool isMobile(int id) {
  final cat = categoryOf(id);
  return cat == MaterialCategory.particle ||
      cat == MaterialCategory.liquid ||
      cat == MaterialCategory.gas;
}
