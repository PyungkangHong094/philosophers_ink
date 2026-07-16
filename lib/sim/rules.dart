import '../core/rng.dart';
import 'grid.dart';
import 'materials.dart';

/// 카테고리별 이동 규칙 (GDD 3.3). 순수 Dart.
///
/// M0에서는 입자(PRIMA)만 이동한다. 액체·기체·전이·반응은 M1에서 이 구조 위에 얹는다.
///
/// 중복 이동 방지: **아래에서 위로** 스캔한다. 입자가 아래로 이동하면 이미 처리된
/// 행으로 들어가므로 같은 틱에 두 번 처리되지 않는다 (dirty 플래그 불필요).
/// 좌우 편향 제거: 프레임마다 가로 스캔 방향을 교차한다.
class Rules {
  final DeterministicRng rng;

  /// 이번 틱의 가로 스캔 방향. 매 step마다 뒤집는다.
  bool _scanLeftToRight = true;

  Rules(this.rng);

  /// reset()에서 스캔 방향까지 초기화해야 결정성이 유지된다.
  void reset() {
    _scanLeftToRight = true;
  }

  /// 한 틱 진행.
  void step(Grid grid) {
    // 맨 아래 행은 이동할 곳이 없으므로 height-2부터.
    for (var y = grid.height - 2; y >= 0; y--) {
      if (_scanLeftToRight) {
        for (var x = 0; x < grid.width; x++) {
          _updateCell(grid, x, y);
        }
      } else {
        for (var x = grid.width - 1; x >= 0; x--) {
          _updateCell(grid, x, y);
        }
      }
    }
    _scanLeftToRight = !_scanLeftToRight;
  }

  void _updateCell(Grid grid, int x, int y) {
    final id = grid.get(x, y);
    switch (categoryOf(id)) {
      case MaterialCategory.particle:
        _updateParticle(grid, x, y);
      case MaterialCategory.none:
      case MaterialCategory.staticSolid:
      case MaterialCategory.liquid: // M1
      case MaterialCategory.gas: // M1
        break;
    }
  }

  /// 입자: 아래 → 아래대각(좌우 랜덤).
  void _updateParticle(Grid grid, int x, int y) {
    // 1) 바로 아래
    if (_tryMove(grid, x, y, x, y + 1)) return;
    // 2) 아래 대각 — 좌우 순서를 매번 랜덤으로 (편향 제거의 미시 보정)
    final leftFirst = rng.nextBool();
    final firstDx = leftFirst ? -1 : 1;
    if (_tryMove(grid, x, y, x + firstDx, y + 1)) return;
    _tryMove(grid, x, y, x - firstDx, y + 1);
  }

  /// 목표 셀이 범위 내이고 EMPTY면 이동. 성공 시 true.
  bool _tryMove(Grid grid, int fromX, int fromY, int toX, int toY) {
    if (!grid.inBounds(toX, toY)) return false;
    if (grid.get(toX, toY) != Material.empty.index) return false;
    grid.set(toX, toY, grid.get(fromX, fromY));
    grid.set(fromX, fromY, Material.empty.index);
    return true;
  }
}
