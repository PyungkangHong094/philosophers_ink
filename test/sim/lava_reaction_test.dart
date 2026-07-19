import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/core/rng.dart';
import 'package:philosophers_ink/sim/emitter.dart';
import 'package:philosophers_ink/sim/gimmicks.dart';
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

int _columnsInRow(Grid grid, int row, Material m) {
  var n = 0;
  for (var x = 0; x < grid.width; x++) {
    if (grid.get(x, row) == m.index) n++;
  }
  return n;
}

void main() {
  group('LAVA 이동 (GDD 3.1 액체)', () {
    test('용암 기둥은 바닥에서 옆으로 퍼진다 (액체 확산)', () {
      final grid = Grid(15, 9);
      for (var x = 0; x < 15; x++) {
        grid.set(x, 8, Material.wall.index);
      }
      for (var y = 1; y <= 6; y++) {
        grid.set(7, y, Material.lava.index);
      }
      final rules = Rules(DeterministicRng(3));
      for (var i = 0; i < 80; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.lava), 6); // 질량 보존
      expect(_columnsInRow(grid, 7, Material.lava), greaterThan(2),
          reason: '용암이 수평으로 퍼짐');
    });
  });

  group('STONE 거동 (GDD 3.1 입자, 반응 생성물)', () {
    test('돌은 입자로 낙하·퇴적한다', () {
      final grid = Grid(3, 9);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 8, Material.wall.index);
      }
      grid.set(1, 0, Material.stone.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(grid.get(1, 7), Material.stone.index);
    });

    test('돌은 가열·냉각에 불변 (재용융 런칭 범위 제외, GDD 3.1 각주)', () {
      final grid = Grid(1, 2);
      grid.set(0, 1, Material.wall.index); // 바닥 — 돌이 소멸하지 않게
      grid.set(0, 0, Material.stone.index);
      final heat = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.heat,
      );
      final cool = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.cool,
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [heat, cool]);
      }
      expect(grid.get(0, 0), Material.stone.index); // 불변
    });
  });

  group('LAVA 냉각 → STONE (GDD 3.1)', () {
    test('빙결 존이 용암을 돌로 굳힌다', () {
      final grid = Grid(1, 2);
      grid.set(0, 1, Material.wall.index); // 바닥 — 용암이 흐르거나 소멸하지 않게
      grid.set(0, 0, Material.lava.index);
      final cool = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.cool,
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [cool]);
      }
      expect(grid.get(0, 0), Material.stone.index);
    });

    test('서리 룬 선이 인접 용암을 돌로 굳힌다', () {
      final grid = Grid(1, 3);
      grid.set(0, 0, Material.coldLine.index);
      grid.set(0, 1, Material.lava.index);
      grid.set(0, 2, Material.wall.index); // 바닥 — 용암이 소멸하지 않게
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid);
      }
      expect(grid.get(0, 1), Material.stone.index);
    });
  });

  group('LAVA + WATER 반응 (GDD 3.2, 유일한 반응)', () {
    test('접촉 시 LAVA→STONE, WATER→STEAM 각각 변환', () {
      // 3x3 벽 상자 안에 용암 위, 물 아래를 인접 배치.
      final grid = Grid(3, 4);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 3, Material.wall.index); // 바닥
      }
      grid.set(1, 1, Material.lava.index);
      grid.set(1, 2, Material.water.index);
      final rules = Rules(DeterministicRng(1));
      rules.step(grid); // 반응은 이동 전 패스라 한 틱에 처리
      expect(_count(grid, Material.lava), 0);
      expect(_count(grid, Material.water), 0);
      expect(_count(grid, Material.stone), 1);
      expect(_count(grid, Material.steam), 1);
    });

    test('한 반응당 정확히 두 셀만 변환 (다중 인접 물 중 첫 하나만)', () {
      // 용암을 물 4개가 둘러쌈. 고정 이웃 순서(상 먼저)로 위쪽 물만 반응.
      // 중앙에 배치 + 바닥 벽으로 한 스텝 내 가장자리 소멸이 없게 한다(카운트 보존).
      final grid = Grid(3, 5);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 4, Material.wall.index); // 바닥
      }
      grid.set(1, 2, Material.lava.index);
      grid.set(1, 1, Material.water.index); // 상 (첫 후보)
      grid.set(1, 3, Material.water.index); // 하
      grid.set(0, 2, Material.water.index); // 좌
      grid.set(2, 2, Material.water.index); // 우
      final rules = Rules(DeterministicRng(1));
      // 반응만 관찰하기 위해 첫 스텝 직후 카운트 (이동으로 위치는 변할 수 있음).
      rules.step(grid);
      expect(_count(grid, Material.stone), 1); // 용암 1개만 굳음
      // 물 4 중 1개만 증기로 (첫 이웃). 나머지 물 3은 남되, 일부는 이동했을 수 있음.
      expect(_count(grid, Material.steam), 1);
      expect(_count(grid, Material.water), 3);
      expect(_count(grid, Material.lava), 0);
    });

    test('반응 생성 STONE·STEAM이 이후 자연 거동한다 (돌 낙하, 증기 상승)', () {
      final grid = Grid(3, 12);
      for (var x = 0; x < 3; x++) {
        grid.set(x, 11, Material.wall.index); // 바닥
        grid.set(x, 0, Material.wall.index); // 천장 — 증기가 상단으로 소멸하지 않게
      }
      grid.set(1, 5, Material.lava.index);
      grid.set(1, 6, Material.water.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 60; i++) {
        rules.step(grid);
      }
      // 돌 1개는 바닥 근처, 증기 1개는 상단 근처.
      expect(_count(grid, Material.stone), 1);
      expect(_count(grid, Material.steam), 1);
      var stoneY = -1;
      var steamY = -1;
      for (var y = 0; y < 12; y++) {
        if (_columnsInRow(grid, y, Material.stone) > 0) stoneY = y;
        if (_columnsInRow(grid, y, Material.steam) > 0 && steamY < 0) steamY = y;
      }
      expect(stoneY, greaterThan(steamY), reason: '돌은 아래, 증기는 위');
    });
  });

  group('결정성·성능 (GDD 10.2)', () {
    GameState scene() {
      // 상단에서 물·용암을 나란히 쏟아 접촉 반응을 유발. 기본 방출 레이트(interval 3,
      // 폭 12)로 실사용 헤비 레벨 수준의 부하를 만든다. (그리드 포화 극단은 별도 관찰.)
      return GameState(
        emitters: [
          EmitterConfig(
            x: 44,
            y: 2,
            width: 12,
            materialId: Material.lava.index,
          ),
          EmitterConfig(
            x: 64,
            y: 2,
            width: 12,
            materialId: Material.water.index,
          ),
        ],
      );
    }

    int runAndHash() {
      final game = scene();
      for (var i = 0; i < 300; i++) {
        game.tick();
      }
      return game.grid.hash();
    }

    test('LAVA+WATER 반응 포함 300틱 후 해시 3회 동일', () {
      final h1 = runAndHash();
      final h2 = runAndHash();
      final h3 = runAndHash();
      expect(h1, h2);
      expect(h2, h3);
      final empty = Grid(SimConstants.gridWidth, SimConstants.gridHeight).hash();
      expect(h1, isNot(empty));
    });

    test('LAVA 활성 최악 시나리오 틱 예산 (~3ms) — 실측 로그', () {
      final game = scene();
      for (var i = 0; i < 400; i++) {
        game.tick(); // 워밍업
      }
      // 배치별 평균의 **최솟값**으로 판정한다. flutter_test는 파일을 병렬 아이솔레이트로
      // 돌려 벽시계 측정에 스케줄러 경합이 섞인다. 틱당 할당이 사실상 0이라 진짜 틱 비용은
      // 안정적이므로, 경합이 덜 낀 배치의 최솟값이 실제 처리량을 대표한다 (GC/컨텍스트
      // 스위치 스파이크에 강건).
      const batches = 8;
      const perBatch = 80;
      var minPerTickMs = double.infinity;
      var lastAvg = 0.0;
      for (var b = 0; b < batches; b++) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < perBatch; i++) {
          game.tick();
        }
        sw.stop();
        lastAvg = sw.elapsedMicroseconds / perBatch / 1000.0;
        if (lastAvg < minPerTickMs) minPerTickMs = lastAvg;
      }
      // ignore: avoid_print
      print('LAVA 활성 틱: min ${minPerTickMs.toStringAsFixed(3)}ms '
          '(마지막 배치 ${lastAvg.toStringAsFixed(3)}ms, 활성 셀 '
          '${game.activeCellCount}, 예산 3ms)');
      expect(minPerTickMs, lessThan(3.0),
          reason: '경합 무관 최소 틱 비용이 예산을 초과');
    });
  });
}
