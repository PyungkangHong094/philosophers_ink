import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

int _countBelowRow(Grid grid, int row, Material m) {
  var n = 0;
  for (var y = row + 1; y < grid.height; y++) {
    for (var x = 0; x < grid.width; x++) {
      if (grid.get(x, y) == m.index) n++;
    }
  }
  return n;
}

/// 대각선 아래(좌하) 삼각형 영역의 물질 수 — y>x인 셀 (대각선 y==x의 좌하).
int _countLowerLeft(Grid grid, Material m) {
  var n = 0;
  for (var y = 0; y < grid.height; y++) {
    for (var x = 0; x < grid.width; x++) {
      if (y > x && grid.get(x, y) == m.index) n++;
    }
  }
  return n;
}

void main() {
  group('모서리 끼어들기 금지 (P1 사선 뚫림 버그)', () {
    test('사선 이음매: 입자가 대각 틈으로 통과하지 못한다', () {
      // 석필 대각 이음매: (1,1)·(2,2)만 채워지고 (2,1)·(1,2)가 비었다(Bresenham 사선).
      // (2,1)에 놓인 입자는 누수 셀 (1,2)로 대각 이동하면 안 된다 (양 직교 이웃이 벽).
      final grid = Grid(4, 4)
        ..set(1, 1, Material.wall.index)
        ..set(2, 2, Material.wall.index)
        ..set(2, 1, Material.prima.index);
      Rules(DeterministicRng(1)).step(grid);
      expect(grid.get(1, 2), Material.empty.index,
          reason: '입자가 대각 이음매를 뚫고 (1,2)로 새면 안 된다');
      // 열린 쪽(우하)으로는 돌아갈 수 있다.
      expect(grid.get(3, 2), Material.prima.index);
    });

    test('중력 반전 사선 이음매: 입자가 위쪽 대각 틈으로 통과하지 못한다', () {
      // 반전(위로 상승). (2,0)·(1,1) 벽, (2,1) 입자. 누수 셀 (1,0).
      final grid = Grid(4, 4)
        ..set(2, 0, Material.wall.index)
        ..set(1, 1, Material.wall.index)
        ..set(2, 1, Material.prima.index);
      Rules(DeterministicRng(1))
        ..setGravityInverted(true)
        ..step(grid);
      expect(grid.get(1, 0), Material.empty.index,
          reason: '반전 시에도 대각 이음매를 뚫으면 안 된다');
      expect(grid.get(3, 0), Material.prima.index);
    });

    test('수평 1픽셀 선: 입자가 통과하지 못하고 위에 퇴적 (과차단 없음 확인)', () {
      // 수평 선은 원래 새지 않았다 — 모서리 규칙이 정상 퇴적을 막지 않는지 확인(대조군).
      final grid = Grid(5, 6);
      for (var x = 0; x < 5; x++) {
        grid.set(x, 3, Material.wall.index); // 수평 석필 선
      }
      final rules = Rules(DeterministicRng(2));
      var injected = 0;
      for (var t = 0; t < 120; t++) {
        if (injected < 6 && grid.get(2, 0) == Material.empty.index) {
          grid.set(2, 0, Material.prima.index);
          injected++;
        }
        rules.step(grid);
      }
      expect(_countBelowRow(grid, 3, Material.prima), 0,
          reason: '수평 선 아래로 입자가 새면 안 된다');
      // 위에는 정상 퇴적(질량 보존).
      var above = 0;
      for (var y = 0; y <= 2; y++) {
        for (var x = 0; x < 5; x++) {
          if (grid.get(x, y) == Material.prima.index) above++;
        }
      }
      expect(above, greaterThan(0), reason: '선 위에 정상 퇴적');
    });

    test('사선 석필 벽: 입자 흐름이 대각선 아래로 새지 않는다', () {
      // 대각선 (i,i) 석필 벽. 위에서 입자를 흘려도 좌하 삼각형(y>x)엔 한 톨도 없어야 한다.
      final grid = Grid(12, 12);
      for (var i = 0; i < 12; i++) {
        grid.set(i, i, Material.wall.index);
      }
      final rules = Rules(DeterministicRng(5));
      var injected = 0;
      for (var t = 0; t < 400; t++) {
        if (injected < 30 && grid.get(6, 0) == Material.empty.index) {
          grid.set(6, 0, Material.prima.index);
          injected++;
        }
        rules.step(grid);
      }
      expect(_countLowerLeft(grid, Material.prima), 0,
          reason: '대각 이음매 누수로 좌하 영역에 입자가 들어가면 안 된다');
    });
  });

  group('결정성 (사선 스트로크 + 모서리 규칙)', () {
    // 실제 버그 시나리오: 래스터라이즈된 대각 석필 스트로크 위로 입자 방출.
    int runAndHash() {
      final game = GameState(emitMaterial: Material.prima.index);
      final s = game.beginStroke(InkType.chalk);
      game.extendStroke(s, 20, 120, 140, 240); // 사선 석필 선
      for (var i = 0; i < 200; i++) {
        game.tick();
      }
      return game.grid.hash();
    }

    test('같은 시드·같은 입력 → 200틱 후 해시 3회 동일 (재현성 유지)', () {
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
