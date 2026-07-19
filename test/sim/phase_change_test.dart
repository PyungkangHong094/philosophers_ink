import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/emitter.dart';
import 'package:philosophers_ink/sim/gimmicks.dart';
import 'package:philosophers_ink/sim/grid.dart';
import 'package:philosophers_ink/sim/materials.dart';
import 'package:philosophers_ink/sim/rules.dart';

/// 한 상전이 이벤트 기록: (materialFrom, materialTo, x, y).
typedef _Event = (int from, int to, int x, int y);

void main() {
  group('상전이 콜백 이벤트 (M5 폴리시)', () {
    test('빙결 온도 존: WATER→ICE 이벤트 (from=WATER, to=ICE, 좌표)', () {
      final grid = Grid(1, 1)..set(0, 0, Material.water.index);
      final events = <_Event>[];
      final rules = Rules(DeterministicRng(1))
        ..onPhaseChange = (f, t, x, y) => events.add((f, t, x, y));
      final zone = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.cool,
      );
      for (var i = 0; i < 100 && grid.get(0, 0) != Material.ice.index; i++) {
        rules.step(grid, zones: [zone]);
      }
      expect(events, isNotEmpty);
      expect(events.first, (Material.water.index, Material.ice.index, 0, 0));
    });

    test('화로 온도 존: WATER→STEAM 이벤트 (from=WATER, to=STEAM, 좌표)', () {
      final grid = Grid(1, 1)..set(0, 0, Material.water.index);
      final events = <_Event>[];
      final rules = Rules(DeterministicRng(1))
        ..onPhaseChange = (f, t, x, y) => events.add((f, t, x, y));
      final zone = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.heat,
      );
      for (var i = 0; i < 100 && grid.get(0, 0) != Material.steam.index; i++) {
        rules.step(grid, zones: [zone]);
      }
      expect(events, isNotEmpty);
      expect(events.first, (Material.water.index, Material.steam.index, 0, 0));
    });

    test('서리 룬 선: 인접 WATER→ICE 시 from/to·좌표 정확히 보고', () {
      // (0,0) 서리 선, (0,1) 물. 물 셀 좌표로 이벤트가 와야 한다.
      final grid = Grid(1, 2)
        ..set(0, 0, Material.coldLine.index)
        ..set(0, 1, Material.water.index);
      final events = <_Event>[];
      final rules = Rules(DeterministicRng(1))
        ..onPhaseChange = (f, t, x, y) => events.add((f, t, x, y));
      for (var i = 0; i < 100 && grid.get(0, 1) != Material.ice.index; i++) {
        rules.step(grid);
      }
      expect(events, isNotEmpty);
      expect(events.first, (Material.water.index, Material.ice.index, 0, 1));
    });

    test('LAVA+WATER 반응: LAVA→STONE + WATER→STEAM 두 이벤트', () {
      final grid = Grid(3, 4);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 3, Material.wall.index);
      }
      grid
        ..set(1, 1, Material.lava.index)
        ..set(1, 2, Material.water.index);
      final events = <_Event>[];
      final rules = Rules(DeterministicRng(1))
        ..onPhaseChange = (f, t, x, y) => events.add((f, t, x, y));
      rules.step(grid);
      expect(events.length, 2);
      expect(
          events.contains(
              (Material.lava.index, Material.stone.index, 1, 1)),
          isTrue);
      expect(
          events.contains(
              (Material.water.index, Material.steam.index, 1, 2)),
          isTrue);
    });
  });

  group('결정성·성능 계약', () {
    GameState freezeScene() => GameState(
          emitters: [
            EmitterConfig(
              x: 70,
              y: 2,
              width: 20,
              materialId: Material.water.index,
            ),
          ],
          temperatureZones: [
            TemperatureZone.rect(
              gridWidth: 160,
              x: 0,
              y: 160,
              width: 160,
              height: 40,
              kind: TemperatureZoneKind.cool,
            ),
          ],
        );

    test('콜백은 관찰 전용 — null이든 기록이든 그리드 해시 동일 (결정성 무영향)', () {
      final gNull = freezeScene();
      for (var i = 0; i < 200; i++) {
        gNull.tick();
      }
      final hashNull = gNull.grid.hash();

      final gObs = freezeScene();
      var count = 0;
      gObs.onPhaseChange = (f, t, x, y) => count++; // 관찰만
      for (var i = 0; i < 200; i++) {
        gObs.tick();
      }
      expect(gObs.grid.hash(), hashNull,
          reason: '관찰 콜백이 시뮬 결과를 바꾸면 안 된다');
      expect(count, greaterThan(0), reason: '실제로 상전이가 발생해 이벤트가 나왔다');
    });

    test('null 콜백 시 성능 회귀 0 — 상전이 대량 시나리오 틱 예산(3ms)', () {
      final game = freezeScene(); // onPhaseChange = null (기본)
      for (var i = 0; i < 400; i++) {
        game.tick(); // 워밍업
      }
      const batches = 8;
      const perBatch = 80;
      var minPerTickMs = double.infinity;
      for (var b = 0; b < batches; b++) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < perBatch; i++) {
          game.tick();
        }
        sw.stop();
        final avg = sw.elapsedMicroseconds / perBatch / 1000.0;
        if (avg < minPerTickMs) minPerTickMs = avg;
      }
      // ignore: avoid_print
      print('상전이 대량(null 콜백) 틱: min ${minPerTickMs.toStringAsFixed(3)}ms '
          '(활성 셀 ${game.activeCellCount}, 예산 3ms)');
      expect(minPerTickMs, lessThan(3.0));
    });
  });
}
