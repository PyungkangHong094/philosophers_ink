import 'dart:typed_data';

import '../core/constants.dart';
import '../core/rng.dart';
import 'gimmicks.dart';
import 'grid.dart';
import 'materials.dart';

/// 상전이 지점을 **관찰만** 하는 옵셔널 콜백 (M5 폴리시, SFX·VFX용).
/// [materialFrom]=전이 전 물질 ID, [materialTo]=전이 후 물질 ID, ([x],[y])=셀 좌표.
/// (from,to)로 이벤트 종류를 구분한다 — 예: WATER→ICE 결빙 crackle, WATER→STEAM 증발 puff,
/// LAVA→STONE·WATER→STEAM 용암+물 치익. 결정성 계약: 콜백은 RNG·그리드 상태를 건드리면
/// 안 된다(관찰 전용). 콜백 호출 순서는 결정적(고정 스캔 순서)이다. null이면 호출 비용 0.
typedef PhaseChangeCallback = void Function(
    int materialFrom, int materialTo, int x, int y);

/// 카테고리별 이동 규칙 + 화염/서리 선 상전이 (GDD 3.3·4.1). 순수 Dart.
///
/// 한 틱 = 상전이 패스 → 이동 패스. 두 패스 모두 결정적 (고정 스캔 + 단일 RNG).
///
/// 중복 이동 방지: **move-stamp**. 한 틱에 어떤 셀로 물질이 들어오면 그 목적지에
/// 현재 틱 번호를 찍고, 스캔이 그 셀에 도달하면 건너뛴다. 입자(하강)와 기체(상승)가
/// 서로 반대 방향으로 움직여도 스캔 순서와 무관하게 한 틱 1회 이동이 보장된다.
/// 좌우 편향은 프레임마다 가로 스캔 방향을 교차해 제거한다.
class Rules {
  final DeterministicRng rng;

  bool _scanLeftToRight = true;
  int _tick = 0;
  Int32List _moveStamp = Int32List(0);

  /// 중력 방향 부호: +1 = 아래(기본), -1 = 위(반전). 이동 규칙·스캔 순서를 미러링한다
  /// (GDD 3.3·6). 런타임 토글이므로 reset()이 기본(+1)으로 되돌린다 → 재시작 결정성.
  int _gravitySign = 1;

  /// 상전이 관찰 콜백 (M5 폴리시, 기본 null). null이면 상전이 지점에서 null 체크 1회만
  /// 하고 넘어가 비용 0. 결정성 무영향(관찰 전용). reset()은 이 배선을 지우지 않는다
  /// (재시작해도 UI의 SFX 연결 유지).
  PhaseChangeCallback? onPhaseChange;

  Rules(this.rng);

  /// 중력이 반전(위 방향)되어 있는가.
  bool get gravityInverted => _gravitySign < 0;

  /// 중력 반전 토글 (GDD 6, 전역 중력 반전 버튼). gameplay가 버튼 입력으로 호출하며,
  /// 입력 시퀀스의 일부로 결정성 로그에 기록된다(계약).
  void setGravityInverted(bool inverted) {
    _gravitySign = inverted ? -1 : 1;
  }

  /// reset()에서 스캔 방향·틱·스탬프·중력까지 초기화해야 재시작 결정성이 성립한다.
  void reset() {
    _scanLeftToRight = true;
    _tick = 0;
    _gravitySign = 1;
    _moveStamp.fillRange(0, _moveStamp.length, 0);
  }

  /// 한 틱 진행: 상전이(룬 → 온도 존) → 반응 → 변성 게이트 → 이동 → 포탈.
  ///
  /// [zones]·[gates]·[portals]는 레벨 데이터(불변). 온도 존은 룬 선과 같은 상전이 패스에서
  /// 존 셀을 가열/냉각하고, 반응 패스는 LAVA+WATER 접촉을 처리하며, 게이트는 이동 전에
  /// 물질을 변환하고, 포탈은 이동 후에 입구→출구 텔레포트를 처리한다. 온도 존만
  /// RNG를 소비(확률 전이), 나머지는 결정적.
  void step(
    Grid grid, {
    List<TransmutationGate> gates = const [],
    List<Portal> portals = const [],
    List<TemperatureZone> zones = const [],
  }) {
    if (_moveStamp.length != grid.cells.length) {
      _moveStamp = Int32List(grid.cells.length);
    }
    _tick++;
    _applyLineTransitions(grid);
    _applyTemperatureZones(grid, zones);
    _applyReactions(grid);
    _applyGates(grid, gates);
    _applyMovement(grid);
    _applyPortals(grid, portals);
    _scanLeftToRight = !_scanLeftToRight;
  }

  // --- 반응 패스 (GDD 3.2, 런칭 범위의 유일한 물질 간 반응) ---

  /// LAVA + WATER 접촉 → STONE + STEAM (접촉한 두 셀이 각각 변환, GDD 3.2). 결정적(RNG 미사용).
  ///
  /// row-major 스캔 + 고정 이웃 순서(상·하·좌·우). LAVA 셀마다 첫 WATER 이웃 하나와만
  /// 반응하고 즉시 반영한다 — 한 반응당 정확히 두 셀. GDD의 "이 외 반응 금지"(스코프 통제)를
  /// 지켜 다른 물질 조합은 건드리지 않는다.
  void _applyReactions(Grid grid) {
    final w = grid.width;
    final h = grid.height;
    final lava = Material.lava.index;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (grid.get(x, y) != lava) continue;
        if (_reactLavaWater(grid, x, y, x, y - 1)) continue;
        if (_reactLavaWater(grid, x, y, x, y + 1)) continue;
        if (_reactLavaWater(grid, x, y, x - 1, y)) continue;
        _reactLavaWater(grid, x, y, x + 1, y);
      }
    }
  }

  /// (lx,ly)의 LAVA와 (wx,wy)가 WATER면 각각 STONE·STEAM으로 변환. 성공 시 true.
  bool _reactLavaWater(Grid grid, int lx, int ly, int wx, int wy) {
    if (!grid.inBounds(wx, wy)) return false;
    if (grid.get(wx, wy) != Material.water.index) return false;
    grid.set(lx, ly, Material.stone.index);
    grid.set(wx, wy, Material.steam.index);
    onPhaseChange?.call(Material.lava.index, Material.stone.index, lx, ly);
    onPhaseChange?.call(Material.water.index, Material.steam.index, wx, wy);
    return true;
  }

  // --- 온도 존 패스 (GDD 6, 레벨 고정 화로/빙결) ---

  /// 각 존의 셀을 매 틱 확률 p로 ±1단계 전이. 룬 선의 _radiateCell과 같은 규칙이되
  /// 인접이 아니라 존 셀 자신에 적용한다. 존·셀 순서 고정 = 결정적.
  void _applyTemperatureZones(Grid grid, List<TemperatureZone> zones) {
    if (zones.isEmpty) return;
    for (final zone in zones) {
      final heat = zone.kind == TemperatureZoneKind.heat;
      final p = zone.probability ??
          (heat ? SimConstants.pHeat : SimConstants.pCold);
      final w = grid.width;
      for (final idx in zone.cellIndices) {
        final id = grid.cells[idx];
        final target = heat ? propsOf(id).heatTo : propsOf(id).coolTo;
        if (target == null) continue; // 전이 불가면 RNG도 소비하지 않는다 (룬과 동일)
        if (rng.nextDouble() < p) {
          grid.cells[idx] = target.index;
          // 존은 셀을 선형 인덱스로 들고 있으니 콜백이 있을 때만 좌표를 환산한다.
          if (onPhaseChange != null) {
            onPhaseChange!(id, target.index, idx % w, idx ~/ w);
          }
        }
      }
    }
  }

  // --- 변성 게이트 패스 (GDD 6) ---

  /// 각 게이트의 존 셀을 검사해 대상 물질을 변환. 게이트·셀 순서 고정 = 결정적.
  void _applyGates(Grid grid, List<TransmutationGate> gates) {
    if (gates.isEmpty) return;
    for (final gate in gates) {
      final to = gate.toMaterial;
      final from = gate.fromMaterial;
      for (final idx in gate.cellIndices) {
        final id = grid.cells[idx];
        if (from != null) {
          if (id != from) continue;
        } else if (!isMobile(id)) {
          continue; // fromMaterial=null → 이동 물질만, 벽·룬 선·EMPTY 보존
        }
        grid.cells[idx] = to;
      }
    }
  }

  // --- 포탈 패스 (GDD 6) ---

  /// 입구 셀의 이동 물질을 빈 출구 셀로 옮긴다. 출구가 막혔으면 대기(입구 유지).
  /// 이번 틱에 이동으로 채워진 입구(_moveStamp==_tick)는 건너뛰어 연쇄 이동을 막는다.
  void _applyPortals(Grid grid, List<Portal> portals) {
    if (portals.isEmpty) return;
    for (final portal in portals) {
      final entry = portal.entryCells;
      final exit = portal.exitCells;
      for (var i = 0; i < entry.length; i++) {
        final e = entry[i];
        if (_moveStamp[e] == _tick) continue; // 이번 틱에 막 들어온 물질은 대기
        final id = grid.cells[e];
        if (!isMobile(id)) continue;
        final x = exit[i];
        if (grid.cells[x] != Material.empty.index) continue; // 출구 막힘 → 대기
        grid.cells[x] = id;
        grid.cells[e] = Material.empty.index;
        _moveStamp[x] = _tick;
      }
    }
  }

  // --- 상전이 패스 (화염/서리 선) ---

  void _applyLineTransitions(Grid grid) {
    final w = grid.width;
    final h = grid.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final id = grid.get(x, y);
        if (id == Material.heatLine.index) {
          _radiate(grid, x, y, heat: true);
        } else if (id == Material.coldLine.index) {
          _radiate(grid, x, y, heat: false);
        }
      }
    }
  }

  /// 인접 4방향 셀을 확률 p로 ±1단계 전이 (전이 대상은 materials 테이블 참조).
  void _radiate(Grid grid, int x, int y, {required bool heat}) {
    final p = heat ? SimConstants.pHeat : SimConstants.pCold;
    // 상·하·좌·우 고정 순서 (결정성).
    _radiateCell(grid, x, y - 1, heat, p);
    _radiateCell(grid, x, y + 1, heat, p);
    _radiateCell(grid, x - 1, y, heat, p);
    _radiateCell(grid, x + 1, y, heat, p);
  }

  void _radiateCell(Grid grid, int x, int y, bool heat, double p) {
    if (!grid.inBounds(x, y)) return;
    final id = grid.get(x, y);
    final target = heat ? propsOf(id).heatTo : propsOf(id).coolTo;
    if (target == null) return; // 전이 불가 물질이면 RNG도 소비하지 않는다
    if (rng.nextDouble() < p) {
      grid.set(x, y, target.index);
      onPhaseChange?.call(id, target.index, x, y);
    }
  }

  // --- 이동 패스 ---

  void _applyMovement(Grid grid) {
    final w = grid.width;
    final h = grid.height;
    // 낙하 물질은 목적지 행을 먼저 처리해야 틱당 1칸이 보장된다. 중력이 아래(+1)면
    // 아래 행(높은 y)부터, 위(-1)면 위 행(낮은 y)부터 스캔한다 — 방향과 함께 미러링.
    if (_gravitySign > 0) {
      for (var y = h - 1; y >= 0; y--) {
        _scanRow(grid, y, w);
      }
    } else {
      for (var y = 0; y < h; y++) {
        _scanRow(grid, y, w);
      }
    }
  }

  void _scanRow(Grid grid, int y, int w) {
    if (_scanLeftToRight) {
      for (var x = 0; x < w; x++) {
        _updateCell(grid, x, y);
      }
    } else {
      for (var x = w - 1; x >= 0; x--) {
        _updateCell(grid, x, y);
      }
    }
  }

  void _updateCell(Grid grid, int x, int y) {
    // 이번 틱에 이 셀로 들어온 물질은 다시 처리하지 않는다.
    if (_moveStamp[grid.index(x, y)] == _tick) return;
    final id = grid.get(x, y);
    switch (categoryOf(id)) {
      case MaterialCategory.particle:
        _updateParticle(grid, x, y, id);
      case MaterialCategory.liquid:
        _updateLiquid(grid, x, y);
      case MaterialCategory.gas:
        _updateGas(grid, x, y);
      case MaterialCategory.none:
      case MaterialCategory.staticSolid:
        break;
    }
  }

  /// 입자: 중력 방향 → 그 대각(좌우 랜덤). granularSlip(ICE)이면 막혔을 때 확률적 옆 미끄러짐.
  /// [dy]=_gravitySign이라 중력 반전 시 이동 방향 전체가 미러링된다(GDD 3.3·6).
  void _updateParticle(Grid grid, int x, int y, int id) {
    final dy = _gravitySign;
    if (_tryFallOrDespawn(grid, x, y, dy)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMoveDiagonal(grid, x, y, firstDx, dy)) return;
    if (_tryMoveDiagonal(grid, x, y, -firstDx, dy)) return;

    if (propsOf(id).granularSlip) {
      // 안식각 낮음: 낙하가 막히면 확률적으로 옆 빈칸으로 한 칸 미끄러진다.
      if (rng.nextDouble() < SimConstants.iceSlipChance) {
        final sideDx = rng.nextBool() ? -1 : 1;
        if (_tryMove(grid, x, y, x + sideDx, y)) return;
        _tryMove(grid, x, y, x - sideDx, y);
      }
    }
  }

  /// 액체: 중력 방향 → 그 대각 → 수평 확산(dispersion까지).
  void _updateLiquid(Grid grid, int x, int y) {
    final dy = _gravitySign;
    if (_tryFallOrDespawn(grid, x, y, dy)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMoveDiagonal(grid, x, y, firstDx, dy)) return;
    if (_tryMoveDiagonal(grid, x, y, -firstDx, dy)) return;
    _spreadHorizontal(grid, x, y, propsOf(grid.get(x, y)).dispersion);
  }

  /// 기체: 중력 반대 방향 → 그 대각 → 수평 확산 (액체의 상하 미러, GDD 3.3).
  /// 기체의 이동 방향(중력 반대)이 곧 기체의 "탈출 방향"이라, 기본 중력에선 상단
  /// 가장자리에서 소멸한다(증기가 하늘로 새는 그림, GDD 정합).
  void _updateGas(Grid grid, int x, int y) {
    final dy = -_gravitySign; // 기체는 중력 반대로 뜬다 → 반전 시 가라앉는다
    if (_tryFallOrDespawn(grid, x, y, dy)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMoveDiagonal(grid, x, y, firstDx, dy)) return;
    if (_tryMoveDiagonal(grid, x, y, -firstDx, dy)) return;
    _spreadHorizontal(grid, x, y, propsOf(grid.get(x, y)).dispersion);
  }

  /// 수평으로 dispersion 칸까지 연속된 빈칸 중 가장 먼 곳으로 이동. 방향은 RNG.
  void _spreadHorizontal(Grid grid, int x, int y, int dispersion) {
    if (dispersion <= 0) return;
    final firstDir = rng.nextBool() ? -1 : 1;
    if (_slide(grid, x, y, firstDir, dispersion)) return;
    _slide(grid, x, y, -firstDir, dispersion);
  }

  /// dir 방향으로 연속 빈칸을 따라 최대 dispersion칸 미끄러진다. 이동 성공 시 true.
  bool _slide(Grid grid, int x, int y, int dir, int dispersion) {
    var dest = x;
    for (var d = 1; d <= dispersion; d++) {
      final nx = x + dir * d;
      if (!grid.inBounds(nx, y) || grid.get(nx, y) != Material.empty.index) {
        break;
      }
      dest = nx;
    }
    if (dest == x) return false;
    grid.set(dest, y, grid.get(x, y));
    grid.set(x, y, Material.empty.index);
    _moveStamp[grid.index(dest, y)] = _tick;
    return true;
  }

  /// 대각 이동 (x,y)→(x+dx, y+dy). **모서리 끼어들기(corner-cut) 금지**: 직교 이웃
  /// (x+dx, y)와 (x, y+dy) 중 하나 이상이 비어 있을 때만 허용한다. 둘 다 막혀 있으면
  /// 대각 이음매를 뚫지 못한다 — 사선 석필 선(Bresenham 대각)이 새는 P1 버그의 근본 차단.
  /// 입자·액체·기체(중력 미러 포함)가 이 규칙을 일관 적용한다.
  bool _tryMoveDiagonal(Grid grid, int x, int y, int dx, int dy) {
    if (!_isEmptyCell(grid, x + dx, y) && !_isEmptyCell(grid, x, y + dy)) {
      return false; // 두 직교 이웃 모두 막힘 → 모서리 통과 불가
    }
    return _tryMove(grid, x, y, x + dx, y + dy);
  }

  /// 범위 내이고 EMPTY인 셀인가. 경계 밖은 (벽처럼) 비어 있지 않은 것으로 본다.
  bool _isEmptyCell(Grid grid, int x, int y) =>
      grid.inBounds(x, y) && grid.get(x, y) == Material.empty.index;

  /// 중력 방향 수직 이동 (x 고정, y+dy). 목적지가 **중력 방향 가장자리 밖**이면 셀을
  /// 소멸(EMPTY)시킨다 — 화면 밖으로 새는 잉여 물질의 물리 구현(GDD 2·5.2). 그리드
  /// 바닥에 무한 퇴적돼 산이 되는 문제를 해소한다. 좌우(수평) 탈출은 대상이 아니다
  /// (여긴 x가 고정이라 y만 경계를 벗어난다). RNG 미소비 = 결정적. 이동/소멸 시 true.
  bool _tryFallOrDespawn(Grid grid, int x, int y, int dy) {
    final ny = y + dy;
    if (ny < 0 || ny >= grid.height) {
      grid.set(x, y, Material.empty.index); // 중력 방향 가장자리 밖 → 소멸
      return true;
    }
    return _tryMove(grid, x, y, x, ny);
  }

  /// 목표 셀이 범위 내이고 EMPTY면 이동 + 목적지 스탬프. 성공 시 true.
  bool _tryMove(Grid grid, int fromX, int fromY, int toX, int toY) {
    if (!grid.inBounds(toX, toY)) return false;
    if (grid.get(toX, toY) != Material.empty.index) return false;
    grid.set(toX, toY, grid.get(fromX, fromY));
    grid.set(fromX, fromY, Material.empty.index);
    _moveStamp[grid.index(toX, toY)] = _tick;
    return true;
  }
}
