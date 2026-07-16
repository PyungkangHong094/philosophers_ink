import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/sim/emitter.dart';
import 'package:philosophers_ink/sim/materials.dart';

int _count(GameState g, Material m) {
  var n = 0;
  for (var i = 0; i < g.grid.cells.length; i++) {
    if (g.grid.cells[i] == m.index) n++;
  }
  return n;
}

void main() {
  test('기본 생성자는 상단 중앙 단일 무한 WATER 방출구', () {
    final game = GameState();
    expect(game.emitterCount, 1);
    expect(game.emitterRemaining(0), isNull, reason: '무한 = null');
    for (var i = 0; i < 10; i++) {
      game.tick();
    }
    expect(_count(game, Material.water), greaterThan(0));
  });

  test('다중 방출구가 각자 물질을 쏟는다', () {
    final game = GameState(emitters: [
      EmitterConfig(
        x: 5,
        y: 2,
        width: 3,
        materialId: Material.prima.index,
        intervalTicks: 1,
      ),
      EmitterConfig(
        x: 50,
        y: 2,
        width: 3,
        materialId: Material.water.index,
        intervalTicks: 1,
      ),
    ]);
    for (var i = 0; i < 6; i++) {
      game.tick();
    }
    expect(_count(game, Material.prima), greaterThan(0));
    expect(_count(game, Material.water), greaterThan(0));
  });

  test('유한 방출구는 total 셀만 쏟고 멈춘다', () {
    final game = GameState(emitters: [
      EmitterConfig(
        x: 10,
        y: 2,
        width: 11, // 밴드는 넓지만 total이 상한
        materialId: Material.ash.index,
        intervalTicks: 1,
        total: 5,
      ),
    ]);
    for (var i = 0; i < 30; i++) {
      game.tick();
    }
    expect(_count(game, Material.ash), 5, reason: '정확히 total만');
    expect(game.emitterRemaining(0), 0);
  });

  test('reset이 방출구 잔량을 복원하고 재방출이 재현된다', () {
    final game = GameState(emitters: [
      EmitterConfig(
        x: 10,
        y: 2,
        width: 5,
        materialId: Material.ash.index,
        intervalTicks: 1,
        total: 5,
      ),
    ]);
    for (var i = 0; i < 10; i++) {
      game.tick();
    }
    expect(_count(game, Material.ash), 5);
    expect(game.emitterRemaining(0), 0);

    game.reset();
    expect(game.emitterRemaining(0), 5, reason: '잔량 복원');
    expect(_count(game, Material.ash), 0, reason: '그리드 클리어');

    for (var i = 0; i < 10; i++) {
      game.tick();
    }
    expect(_count(game, Material.ash), 5, reason: '재방출 재현');
  });

  test('재 방출구: ashRatio가 물질과 ASH를 결정성으로 혼합', () {
    List<int> mix(int seed) {
      final game = GameState(seed: seed, emitters: [
        EmitterConfig(
          x: 40,
          y: 2,
          width: 10,
          materialId: Material.water.index,
          intervalTicks: 1,
          total: 40,
          ashRatio: 0.5,
        ),
      ]);
      for (var i = 0; i < 30; i++) {
        game.tick();
      }
      return [_count(game, Material.water), _count(game, Material.ash)];
    }

    final a = mix(123);
    expect(a[0] + a[1], 40, reason: '총 방출 = total');
    expect(a[0], greaterThan(0), reason: '물도 있고');
    expect(a[1], greaterThan(0), reason: '재도 있다');
    // 같은 시드 → 같은 혼합 (결정성).
    expect(mix(123), a);
  });

  group('consumeCell (플라스크 착수 소비 계약)', () {
    test('셀을 비우고 비어진 물질 ID를 반환', () {
      final game = GameState(emitters: []);
      game.grid.set(30, 40, Material.water.index);
      expect(game.consumeCell(30, 40), Material.water.index);
      expect(game.grid.get(30, 40), Material.empty.index);
    });

    test('EMPTY·범위 밖은 0(EMPTY) 반환, 변경 없음', () {
      final game = GameState(emitters: []);
      expect(game.consumeCell(30, 40), Material.empty.index);
      expect(game.consumeCell(-1, 0), Material.empty.index);
      expect(game.consumeCell(0, 999999), Material.empty.index);
    });
  });
}
