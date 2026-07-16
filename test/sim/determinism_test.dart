import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

/// 같은 시드 + 같은 입력 시퀀스로 N틱 돌리고 그리드 해시를 낸다.
int _runAndHash(int seed) {
  final game = GameState(seed: seed);
  // 결정적 입력: 대각 석필 선 하나 (물을 가두는 벽).
  final stroke = game.beginStroke(InkType.chalk);
  game.extendStroke(stroke, 10, 200, 150, 260);
  for (var i = 0; i < 300; i++) {
    game.tick();
  }
  return game.grid.hash();
}

void main() {
  test('같은 시드·같은 입력 → 300틱 후 해시가 3회 모두 동일', () {
    final h1 = _runAndHash(SimConstants.defaultSeed);
    final h2 = _runAndHash(SimConstants.defaultSeed);
    final h3 = _runAndHash(SimConstants.defaultSeed);
    expect(h1, h2);
    expect(h2, h3);
    // 시뮬이 실제로 무언가를 했는지 (빈 그리드가 아님) 확인 — 테스트의 의미 보장.
    final empty = Grid(SimConstants.gridWidth, SimConstants.gridHeight).hash();
    expect(h1, isNot(empty));
  });

  test('reset 후 같은 입력을 재현하면 해시가 동일 (재시작 결정성)', () {
    final game = GameState();
    void playInput() {
      final s = game.beginStroke(InkType.chalk);
      game.extendStroke(s, 10, 200, 150, 260);
      for (var i = 0; i < 200; i++) {
        game.tick();
      }
    }

    playInput();
    final first = game.grid.hash();

    // GDD 10.5: 3회 연속 재시작 동일 동작.
    for (var r = 0; r < 3; r++) {
      game.reset();
      playInput();
      expect(game.grid.hash(), first, reason: 'reset #$r 후 재현 실패');
    }
  });

  // RNG가 시뮬에 실제로 반영되는지 — 대각 타이브레이크로 검증.
  // (전체 방출 시나리오는 조밀 퇴적으로 형상이 수렴해 시드 차이가 사라질 수 있으므로,
  //  좌우가 모두 열린 받침 위 단일 입자로 방향 분기를 직접 관찰한다.)
  test('대각 타이브레이크에 RNG가 반영된다 (시드에 따라 좌/우로 갈린다)', () {
    int landSideForSeed(int seed) {
      final grid = Grid(3, 3);
      grid.set(1, 2, Material.wall.index); // 받침 기둥
      grid.set(1, 1, Material.prima.index); // 그 위 입자 (아래 막힘)
      Rules(DeterministicRng(seed)).step(grid);
      if (grid.get(0, 2) == Material.prima.index) return -1; // 좌
      if (grid.get(2, 2) == Material.prima.index) return 1; // 우
      return 0;
    }

    final sides = {for (var s = 1; s <= 20; s++) landSideForSeed(s)};
    expect(sides.contains(-1) && sides.contains(1), isTrue,
        reason: '시드에 따라 좌·우가 모두 나와야 RNG가 결과에 영향');
  });
}
