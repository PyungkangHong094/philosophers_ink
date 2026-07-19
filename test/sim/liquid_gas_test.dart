import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

int _count(Grid grid, Material m) {
  var n = 0;
  for (var i = 0; i < grid.cells.length; i++) {
    if (grid.cells[i] == m.index) n++;
  }
  return n;
}

/// row에서 물질 m이 차지한 서로 다른 열의 수.
int _columnsInRow(Grid grid, int row, Material m) {
  var n = 0;
  for (var x = 0; x < grid.width; x++) {
    if (grid.get(x, row) == m.index) n++;
  }
  return n;
}

void main() {
  group('액체(WATER) 확산', () {
    test('물 기둥은 바닥에서 옆으로 퍼져 평평해진다 (dispersion)', () {
      final grid = Grid(15, 9);
      for (var x = 0; x < 15; x++) {
        grid.set(x, 8, Material.wall.index); // 바닥
      }
      // 가운데 열에 물 기둥 6칸
      for (var y = 1; y <= 6; y++) {
        grid.set(7, y, Material.water.index);
      }
      final rules = Rules(DeterministicRng(3));
      for (var i = 0; i < 80; i++) {
        rules.step(grid);
      }
      // 질량 보존: 물은 그리드를 벗어나지 못한다.
      expect(_count(grid, Material.water), 6);
      // 바닥 바로 위 행(7)에 여러 열로 퍼졌다 (기둥 1열 → 다열).
      expect(_columnsInRow(grid, 7, Material.water), greaterThan(2),
          reason: '물이 수평으로 퍼져 평평해짐');
    });

    test('물은 벽으로 막은 웅덩이 안에 고인다', () {
      final grid = Grid(9, 9);
      for (var x = 0; x < 9; x++) {
        grid.set(x, 8, Material.wall.index); // 바닥
      }
      grid.set(2, 7, Material.wall.index); // 좌 벽
      grid.set(6, 7, Material.wall.index); // 우 벽
      for (var y = 5; y <= 8; y++) {
        grid
          ..set(2, y, Material.wall.index)
          ..set(6, y, Material.wall.index);
      }
      // 웅덩이(x 3..5) 위에 물 투입
      for (var i = 0; i < 40; i++) {
        if (grid.get(4, 0) == Material.empty.index) {
          grid.set(4, 0, Material.water.index);
        }
        Rules(DeterministicRng(1)).step(grid);
      }
      // 물이 웅덩이 바닥 행(7)의 3..5 안에 고여 있다.
      var pooled = 0;
      for (var x = 3; x <= 5; x++) {
        if (grid.get(x, 7) == Material.water.index) pooled++;
      }
      expect(pooled, greaterThan(0), reason: '벽 사이에 물이 고임');
    });
  });

  group('기체(STEAM) 상승', () {
    test('증기는 위로 올라 천장 아래에 모인다 (액체의 상하 미러)', () {
      final grid = Grid(5, 12);
      for (var x = 0; x < 5; x++) {
        grid.set(x, 0, Material.wall.index); // 천장 — 없으면 상단으로 소멸(배수 규칙)
      }
      grid.set(2, 10, Material.steam.index); // 하단 근처
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 16; i++) {
        rules.step(grid);
      }
      // 천장 바로 아래 행(1)에 증기가 도달, 원위치는 비었다.
      expect(_columnsInRow(grid, 1, Material.steam), 1);
      expect(grid.get(2, 10), Material.empty.index);
      // 하단부에는 증기 없음.
      for (var y = 6; y < 12; y++) {
        expect(_columnsInRow(grid, y, Material.steam), 0);
      }
    });
  });

  group('얼음(ICE) 안식각', () {
    // ICE는 granularSlip으로 옆으로 미끄러져 PRIMA보다 더미가 넓고 평평하다.
    // 넓은 그리드에 한정된 양만 흘려 포화(그리드 폭 도달)를 피하고, 더미의
    // 최대 확산 폭으로 비교한다.
    int maxPileWidth(Material material) {
      final grid = Grid(41, 40);
      for (var x = 0; x < 41; x++) {
        grid.set(x, 39, Material.wall.index); // 바닥
      }
      final rules = Rules(DeterministicRng(7));
      var injected = 0;
      for (var t = 0; t < 600; t++) {
        if (injected < 60 && grid.get(20, 0) == Material.empty.index) {
          grid.set(20, 0, material.index);
          injected++;
        }
        rules.step(grid);
      }
      var widest = 0;
      for (var y = 0; y < 39; y++) {
        final w = _columnsInRow(grid, y, material);
        if (w > widest) widest = w;
      }
      return widest;
    }

    test('얼음 더미가 프리마 더미보다 넓게 퍼진다', () {
      final iceWidth = maxPileWidth(Material.ice);
      final primaWidth = maxPileWidth(Material.prima);
      expect(iceWidth, greaterThan(primaWidth),
          reason: 'ICE 안식각↓ → 더 잘 퍼짐 (ice=$iceWidth, prima=$primaWidth)');
    });
  });
}
