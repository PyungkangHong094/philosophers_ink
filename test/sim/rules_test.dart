import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

void main() {
  group('입자 낙하 규칙', () {
    test('빈 공간 위 입자는 한 틱에 바로 아래로 떨어진다', () {
      final grid = Grid(5, 5);
      grid.set(2, 0, Material.prima.index);
      Rules(DeterministicRng(1)).step(grid);
      expect(grid.get(2, 0), Material.empty.index);
      expect(grid.get(2, 1), Material.prima.index);
    });

    test('입자는 벽 위에 얹혀 멈추고 벽을 통과하지 못한다', () {
      final grid = Grid(5, 6);
      for (var x = 0; x < 5; x++) {
        grid.set(x, 5, Material.wall.index);
      }
      grid.set(2, 0, Material.prima.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(grid.get(2, 4), Material.prima.index, reason: '벽 바로 위에 안착');
      expect(grid.get(2, 5), Material.wall.index, reason: '벽은 그대로');
    });
  });

  group('퇴적', () {
    test('1폭 기둥에서 입자가 벽 위로 차곡차곡 쌓인다', () {
      final grid = Grid(1, 6);
      grid.set(0, 5, Material.wall.index); // 바닥
      final rules = Rules(DeterministicRng(1));
      // 매 틱 상단이 비면 방출 → 기둥이 가득 찬다.
      for (var t = 0; t < 20; t++) {
        if (grid.get(0, 0) == Material.empty.index) {
          grid.set(0, 0, Material.prima.index);
        }
        rules.step(grid);
      }
      for (var y = 0; y < 5; y++) {
        expect(grid.get(0, y), Material.prima.index, reason: 'row $y 채워짐');
      }
      expect(grid.get(0, 5), Material.wall.index);
    });

    test('입자는 바닥 벽 아래로 새지 않는다 (질량 보존)', () {
      final grid = Grid(7, 24);
      for (var x = 0; x < 7; x++) {
        grid.set(x, 23, Material.wall.index);
      }
      final rules = Rules(DeterministicRng(42));
      for (var t = 0; t < 60; t++) {
        if (grid.get(3, 0) == Material.empty.index) {
          grid.set(3, 0, Material.prima.index);
        }
        rules.step(grid);
      }
      // 벽 행 아래는 존재하지 않고, 벽 행 자체는 온전.
      for (var x = 0; x < 7; x++) {
        expect(grid.get(x, 23), Material.wall.index);
      }
      // 더미가 바닥 근처까지 쌓였다.
      var restingNearFloor = 0;
      for (var x = 0; x < 7; x++) {
        if (grid.get(x, 22) == Material.prima.index) restingNearFloor++;
      }
      expect(restingNearFloor, greaterThan(0), reason: '바닥 위에 퇴적');
    });
  });

  test('한 틱에 한 셀은 한 칸만 이동한다 (중복 이동 방지)', () {
    // 여러 입자가 위에서 아래로 정렬된 열. 한 틱 뒤 각자 정확히 한 칸씩만 내려간다.
    final grid = Grid(1, 10);
    grid.set(0, 0, Material.prima.index);
    grid.set(0, 1, Material.prima.index);
    Rules(DeterministicRng(1)).step(grid);
    // 맨 아래(1)가 2로, 위(0)가 1로. 둘 다 한 칸씩만.
    expect(grid.get(0, 0), Material.empty.index);
    expect(grid.get(0, 1), Material.prima.index);
    expect(grid.get(0, 2), Material.prima.index);
    expect(grid.get(0, 3), Material.empty.index);
  });
}
