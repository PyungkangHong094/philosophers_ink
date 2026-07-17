/// 기믹 스펙(제네릭 [GimmickSpec]) → sim 인스턴스 변환 (GDD 6장). 순수 Dart.
///
/// [loadLevelFromJson]이 항상 [validateLevel]을 통과시키므로, 이 빌더는 **검증된**
/// 파라미터를 받는다고 가정한다(방어적 fallback은 두되 재검증은 하지 않는다).
/// sim의 공개 타입([TransmutationGate]/[Portal]/[TemperatureZone])만 조립하고
/// sim 내부 규칙은 건드리지 않는다 (소유권 경계: sim-engineer).
///
/// 좌표계는 sim 계약과 동일한 row-major (`y * gridWidth + x`).
library;

import '../sim/gimmicks.dart';
import 'level_model.dart';

/// 레벨의 기믹을 sim이 소비하는 형태로 묶은 결과 (레벨 데이터, 불변).
class GimmickBundle {
  /// 변성 게이트 (이동 전 물질 변환).
  final List<TransmutationGate> gates;

  /// 포탈 (이동 후 순간이동).
  final List<Portal> portals;

  /// 온도 존 (상전이 패스에서 존 셀 가열/냉각).
  final List<TemperatureZone> zones;

  /// 중력 반전 버튼 기믹이 하나라도 있는가 → 게임플레이가 토글 버튼을 노출.
  final bool hasGravityFlip;

  const GimmickBundle({
    this.gates = const [],
    this.portals = const [],
    this.zones = const [],
    this.hasGravityFlip = false,
  });

  static const GimmickBundle empty = GimmickBundle();
}

/// 기믹 스펙 목록을 [GimmickBundle]로 변환한다. [gridWidth]는 인덱스 계산용.
GimmickBundle buildGimmicks(List<GimmickSpec> specs, {required int gridWidth}) {
  if (specs.isEmpty) return GimmickBundle.empty;
  final gates = <TransmutationGate>[];
  final portals = <Portal>[];
  final zones = <TemperatureZone>[];
  var hasGravityFlip = false;

  for (final g in specs) {
    switch (g.type) {
      case GimmickType.varianceGate:
        gates.add(_buildGate(g.params, gridWidth));
      case GimmickType.portal:
        portals.add(_buildPortal(g.params, gridWidth));
      case GimmickType.tempZone:
        zones.add(_buildZone(g.params, gridWidth));
      case GimmickType.gravityFlip:
        hasGravityFlip = true;
      case GimmickType.ashEmitter:
        // 재 방출구는 방출구 ash_ratio가 실제 메커니즘 — 이 기믹은 마커일 뿐 배선 없음.
        break;
      default:
        // 검증기가 이미 걸러냈어야 한다. 방어적으로 무시.
        break;
    }
  }

  return GimmickBundle(
    gates: gates,
    portals: portals,
    zones: zones,
    hasGravityFlip: hasGravityFlip,
  );
}

TransmutationGate _buildGate(Map<String, dynamic> p, int gridWidth) {
  final to = materialFromName(_str(p[GimmickParamKey.to]));
  final fromName = p[GimmickParamKey.from];
  final from =
      fromName == null ? null : materialFromName(_str(fromName));
  return TransmutationGate.rect(
    gridWidth: gridWidth,
    x: _int(p[GimmickParamKey.x]),
    y: _int(p[GimmickParamKey.y]),
    width: _int(p[GimmickParamKey.w]),
    height: _int(p[GimmickParamKey.h]),
    toMaterial: (to ?? Material.empty).index,
    fromMaterial: from?.index,
  );
}

Portal _buildPortal(Map<String, dynamic> p, int gridWidth) {
  final entry = _rect(p[GimmickParamKey.entry]);
  final exit = _rect(p[GimmickParamKey.exit]);
  return Portal(
    entryCells: _rectCells(gridWidth, entry),
    exitCells: _rectCells(gridWidth, exit),
  );
}

TemperatureZone _buildZone(Map<String, dynamic> p, int gridWidth) {
  final kind = _str(p[GimmickParamKey.kind]) == kTempZoneHeat
      ? TemperatureZoneKind.heat
      : TemperatureZoneKind.cool;
  final probRaw = p[GimmickParamKey.probability];
  return TemperatureZone.rect(
    gridWidth: gridWidth,
    x: _int(p[GimmickParamKey.x]),
    y: _int(p[GimmickParamKey.y]),
    width: _int(p[GimmickParamKey.w]),
    height: _int(p[GimmickParamKey.h]),
    kind: kind,
    probability: probRaw is num ? probRaw.toDouble() : null,
  );
}

/// 4-필드 rect(x,y,w,h)로 압축한 값. 파싱 실패는 0으로 fallback(검증기가 이미 방어).
class _Rect {
  final int x;
  final int y;
  final int w;
  final int h;
  const _Rect(this.x, this.y, this.w, this.h);
}

_Rect _rect(dynamic v) {
  if (v is! Map) return const _Rect(0, 0, 1, 1);
  final m = v.cast<String, dynamic>();
  return _Rect(
    _int(m[GimmickParamKey.x]),
    _int(m[GimmickParamKey.y]),
    _int(m[GimmickParamKey.w], fallback: 1),
    _int(m[GimmickParamKey.h], fallback: 1),
  );
}

/// rect를 row-major 순서(`y*gridWidth+x`)의 셀 인덱스 목록으로.
List<int> _rectCells(int gridWidth, _Rect r) {
  final cells = <int>[];
  for (var yy = r.y; yy < r.y + r.h; yy++) {
    for (var xx = r.x; xx < r.x + r.w; xx++) {
      cells.add(yy * gridWidth + xx);
    }
  }
  return cells;
}

int _int(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return fallback;
}

String _str(dynamic v) => v is String ? v : '';
