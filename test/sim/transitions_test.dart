import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

/// 이동이 불가능하도록 가둔 세로 3칸 셀에서 상전이 체인만 관찰한다.
/// 가운데 셀이 전이 물질을 담고, 아래/위는 선/벽이라 어디로도 못 움직인다.
Grid _heatChainCell() {
  final grid = Grid(1, 3);
  grid.set(0, 0, Material.wall.index); // 상단 캡 (STEAM이 못 빠져나감)
  grid.set(0, 1, Material.ice.index); // 전이 대상 (갇힘)
  grid.set(0, 2, Material.heatLine.index); // 화염 룬 (아래에서 가열)
  return grid;
}

Grid _coldChainCell() {
  final grid = Grid(1, 3);
  grid.set(0, 0, Material.coldLine.index); // 서리 룬 (위에서 냉각)
  grid.set(0, 1, Material.steam.index); // 전이 대상 (갇힘)
  grid.set(0, 2, Material.wall.index); // 바닥 (WATER/ICE가 못 빠짐)
  return grid;
}

void main() {
  group('화염 룬 가열 체인 (ICE→WATER→STEAM)', () {
    test('갇힌 얼음이 결국 물을 거쳐 증기가 된다', () {
      final grid = _heatChainCell();
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 400; i++) {
        rules.step(grid);
      }
      expect(grid.get(0, 1), Material.steam.index);
    });

    test('증기는 더 가열해도 불변 (heatTo == null)', () {
      final grid = _heatChainCell();
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 800; i++) {
        rules.step(grid);
      }
      expect(grid.get(0, 1), Material.steam.index, reason: 'STEAM에서 멈춤');
    });
  });

  group('서리 룬 냉각 체인 (STEAM→WATER→ICE)', () {
    test('갇힌 증기가 결국 물을 거쳐 얼음이 된다', () {
      final grid = _coldChainCell();
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 400; i++) {
        rules.step(grid);
      }
      expect(grid.get(0, 1), Material.ice.index);
    });
  });

  test('불활성 물질(PRIMA)은 화염 룬 옆에서도 불변', () {
    final grid = Grid(1, 3);
    grid.set(0, 0, Material.prima.index); // 화염 룬 위 (이동도 막힘)
    grid.set(0, 1, Material.heatLine.index);
    grid.set(0, 2, Material.wall.index);
    final rules = Rules(DeterministicRng(1));
    for (var i = 0; i < 300; i++) {
      rules.step(grid);
    }
    expect(grid.get(0, 0), Material.prima.index);
  });

  test('전이는 결정적 — 같은 시드로 N틱 후 그리드 해시 동일', () {
    int hashAfter(int seed, int ticks) {
      final grid = _heatChainCell();
      final rules = Rules(DeterministicRng(seed));
      for (var i = 0; i < ticks; i++) {
        rules.step(grid);
      }
      return grid.hash();
    }

    final a = hashAfter(9, 40);
    final b = hashAfter(9, 40);
    expect(a, b);
    // 확률 전이라 시드가 다르면 40틱 시점 상태가 갈릴 수 있다 (전이 타이밍 차이).
    // 최소한 결정성(동일 시드 동일)은 고정한다.
  });
}
