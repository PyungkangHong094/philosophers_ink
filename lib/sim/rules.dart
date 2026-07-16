import 'dart:typed_data';

import '../core/constants.dart';
import '../core/rng.dart';
import 'grid.dart';
import 'materials.dart';

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

  Rules(this.rng);

  /// reset()에서 스캔 방향·틱·스탬프까지 초기화해야 재시작 결정성이 성립한다.
  void reset() {
    _scanLeftToRight = true;
    _tick = 0;
    _moveStamp.fillRange(0, _moveStamp.length, 0);
  }

  /// 한 틱 진행: 상전이 → 이동.
  void step(Grid grid) {
    if (_moveStamp.length != grid.cells.length) {
      _moveStamp = Int32List(grid.cells.length);
    }
    _tick++;
    _applyLineTransitions(grid);
    _applyMovement(grid);
    _scanLeftToRight = !_scanLeftToRight;
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
    }
  }

  // --- 이동 패스 ---

  void _applyMovement(Grid grid) {
    final w = grid.width;
    for (var y = grid.height - 1; y >= 0; y--) {
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

  /// 입자: 아래 → 아래대각(좌우 랜덤). granularSlip(ICE)이면 막혔을 때 확률적 옆 미끄러짐.
  void _updateParticle(Grid grid, int x, int y, int id) {
    if (_tryMove(grid, x, y, x, y + 1)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMove(grid, x, y, x + firstDx, y + 1)) return;
    if (_tryMove(grid, x, y, x - firstDx, y + 1)) return;

    if (propsOf(id).granularSlip) {
      // 안식각 낮음: 낙하가 막히면 확률적으로 옆 빈칸으로 한 칸 미끄러진다.
      if (rng.nextDouble() < SimConstants.iceSlipChance) {
        final sideDx = rng.nextBool() ? -1 : 1;
        if (_tryMove(grid, x, y, x + sideDx, y)) return;
        _tryMove(grid, x, y, x - sideDx, y);
      }
    }
  }

  /// 액체: 아래 → 아래대각 → 수평 확산(dispersion까지).
  void _updateLiquid(Grid grid, int x, int y) {
    if (_tryMove(grid, x, y, x, y + 1)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMove(grid, x, y, x + firstDx, y + 1)) return;
    if (_tryMove(grid, x, y, x - firstDx, y + 1)) return;
    _spreadHorizontal(grid, x, y, propsOf(grid.get(x, y)).dispersion);
  }

  /// 기체: 위 → 위대각 → 수평 확산 (액체의 상하 미러, GDD 3.3).
  void _updateGas(Grid grid, int x, int y) {
    if (_tryMove(grid, x, y, x, y - 1)) return;
    final firstDx = rng.nextBool() ? -1 : 1;
    if (_tryMove(grid, x, y, x + firstDx, y - 1)) return;
    if (_tryMove(grid, x, y, x - firstDx, y - 1)) return;
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
