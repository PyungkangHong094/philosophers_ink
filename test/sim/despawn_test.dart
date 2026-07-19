import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/game_state.dart';
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

void main() {
  group('중력 방향 가장자리 소멸 (GDD 5.2 배수 규칙)', () {
    test('바닥 개방: 입자가 그리드 바닥 밖으로 소멸한다', () {
      final grid = Grid(3, 5)..set(1, 0, Material.prima.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.prima), 0, reason: '바닥으로 빠져 소멸해야 한다');
    });

    test('액체도 바닥 밖으로 소멸한다', () {
      final grid = Grid(3, 5)..set(1, 0, Material.water.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.water), 0);
    });

    test('중력 반전: 입자가 천장 밖으로 소멸한다', () {
      final grid = Grid(3, 5)..set(1, 4, Material.prima.index);
      final rules = Rules(DeterministicRng(1))..setGravityInverted(true);
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.prima), 0, reason: '반전 시 천장으로 소멸');
    });

    test('기체는 상단 가장자리에서 소멸한다 (증기가 하늘로 샘)', () {
      final grid = Grid(3, 5)..set(1, 4, Material.steam.index);
      final rules = Rules(DeterministicRng(1)); // 기본 중력
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.steam), 0, reason: '기체는 위로 새어 소멸');
    });

    test('명시적 WALL 바닥 위에서는 소멸하지 않고 퇴적한다', () {
      final grid = Grid(3, 5);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 4, Material.wall.index); // 바닥을 벽으로 명시
      }
      grid.set(1, 0, Material.prima.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.prima), 1, reason: '벽 위에는 남아 퇴적');
      expect(grid.get(1, 3), Material.prima.index, reason: '벽 바로 위 행에 정지');
    });

    test('가장자리 행에 정지한 정적 물질(WALL)은 소멸 대상이 아니다', () {
      final grid = Grid(3, 5);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 4, Material.wall.index);
      }
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.wall), 3, reason: '정적 물질은 이동/소멸 없음');
    });
  });

  group('결정성 (바닥 개방 + 소멸)', () {
    int runAndHash() {
      // 바닥이 열린 기본 그리드에 물을 무한 방출 → 낙하·소멸이 정상 순환.
      final game = GameState(emitMaterial: Material.water.index);
      final s = game.beginStroke(InkType.chalk);
      game.extendStroke(s, 20, 160, 140, 200); // 정적 벽(해시 비-공집합 보장)
      for (var i = 0; i < 250; i++) {
        game.tick();
      }
      return game.grid.hash();
    }

    test('같은 시드·같은 입력 → 250틱 후 해시 3회 동일', () {
      final h1 = runAndHash();
      final h2 = runAndHash();
      final h3 = runAndHash();
      expect(h1, h2);
      expect(h2, h3);
      final empty = Grid(SimConstants.gridWidth, SimConstants.gridHeight).hash();
      expect(h1, isNot(empty));
    });
  });
}
