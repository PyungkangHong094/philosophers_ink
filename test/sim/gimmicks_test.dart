import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/rng.dart';
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

/// 바닥 한 줄을 벽으로 채운다 (입자가 대각으로 새지 않도록).
void _floor(Grid grid, int row) {
  for (var x = 0; x < grid.width; x++) {
    grid.set(x, row, Material.wall.index);
  }
}

void main() {
  group('변성 게이트 (GDD 6)', () {
    test('지정 물질만 변환한다 (PRIMA→WATER), 다른 이동 물질·정적은 보존', () {
      final grid = Grid(5, 5);
      grid.set(1, 2, Material.prima.index); // 변환 대상
      grid.set(2, 2, Material.ice.index); // 대상 아님 → 보존
      grid.set(3, 2, Material.wall.index); // 정적 → 보존
      final gate = TransmutationGate.rect(
        gridWidth: 5,
        x: 0,
        y: 2,
        width: 5,
        height: 1,
        fromMaterial: Material.prima.index,
        toMaterial: Material.water.index,
      );
      final rules = Rules(DeterministicRng(1));
      rules.step(grid, gates: [gate]);
      // PRIMA는 게이트에서 WATER가 되었고(이후 이동으로 위치는 변할 수 있음),
      // 원래 PRIMA는 그리드에 남지 않는다.
      expect(_count(grid, Material.prima), 0);
      expect(_count(grid, Material.water), 1);
      // ICE·WALL은 그대로.
      expect(_count(grid, Material.ice), 1);
      expect(_count(grid, Material.wall), 1);
    });

    test('fromMaterial=null이면 모든 이동 물질을 변환, 정적·EMPTY는 건드리지 않는다', () {
      final grid = Grid(4, 1);
      grid.set(0, 0, Material.prima.index); // 입자
      grid.set(1, 0, Material.steam.index); // 기체
      grid.set(2, 0, Material.wall.index); // 정적 → 보존
      // (3,0) EMPTY → 보존
      final gate = TransmutationGate.rect(
        gridWidth: 4,
        x: 0,
        y: 0,
        width: 4,
        height: 1,
        toMaterial: Material.ash.index,
      );
      Rules(DeterministicRng(1)).step(grid, gates: [gate]);
      expect(grid.get(0, 0), Material.ash.index);
      expect(grid.get(1, 0), Material.ash.index);
      expect(grid.get(2, 0), Material.wall.index);
      expect(grid.get(3, 0), Material.empty.index);
    });

    test('게이트 존 위로 떨어지는 입자 흐름이 통과하며 변환된다', () {
      final grid = Grid(3, 12);
      _floor(grid, 11);
      // y=6 전체를 덮는 1셀 두께 게이트: PRIMA→WATER.
      final gate = TransmutationGate.rect(
        gridWidth: 3,
        x: 0,
        y: 6,
        width: 3,
        height: 1,
        fromMaterial: Material.prima.index,
        toMaterial: Material.water.index,
      );
      final rules = Rules(DeterministicRng(2));
      var injected = 0;
      for (var t = 0; t < 120; t++) {
        if (injected < 8 && grid.get(1, 0) == Material.empty.index) {
          grid.set(1, 0, Material.prima.index);
          injected++;
        }
        rules.step(grid, gates: [gate]);
      }
      // 모든 PRIMA가 게이트를 지나며 WATER가 되어 바닥에 고였다.
      expect(_count(grid, Material.prima), 0);
      expect(_count(grid, Material.water), 8);
    });
  });

  group('중력 반전 (GDD 3.3·6)', () {
    test('반전 시 입자는 위로 떠오른다', () {
      final grid = Grid(3, 9);
      grid.set(1, 4, Material.prima.index);
      final rules = Rules(DeterministicRng(1))..setGravityInverted(true);
      expect(rules.gravityInverted, isTrue);
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      // 최상단 행에 도달, 원위치는 비었다.
      expect(grid.get(1, 0), Material.prima.index);
      expect(grid.get(1, 4), Material.empty.index);
    });

    test('반전 시 기체는 가라앉는다', () {
      final grid = Grid(3, 9);
      grid.set(1, 4, Material.steam.index);
      final rules = Rules(DeterministicRng(1))..setGravityInverted(true);
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      // 최하단 행으로 가라앉는다(바닥에서 수평 확산하므로 열은 특정하지 않는다).
      var steamInBottomRow = 0;
      for (var x = 0; x < 3; x++) {
        if (grid.get(x, 8) == Material.steam.index) steamInBottomRow++;
      }
      expect(steamInBottomRow, 1);
      expect(grid.get(1, 4), Material.empty.index);
    });

    test('반전 해제 시 정상 중력으로 복귀한다 (입자는 다시 낙하)', () {
      final grid = Grid(3, 9);
      grid.set(1, 4, Material.prima.index);
      final rules = Rules(DeterministicRng(1))..setGravityInverted(true);
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(grid.get(1, 0), Material.prima.index); // 위로 붙음
      rules.setGravityInverted(false);
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(grid.get(1, 8), Material.prima.index); // 다시 바닥
      expect(rules.gravityInverted, isFalse);
    });

    test('reset()이 중력을 기본(아래)으로 되돌린다', () {
      final rules = Rules(DeterministicRng(1))..setGravityInverted(true);
      rules.reset();
      expect(rules.gravityInverted, isFalse);
    });
  });

  group('포탈 (GDD 6)', () {
    test('입구의 이동 물질이 빈 출구로 순간이동한다', () {
      final grid = Grid(5, 3);
      _floor(grid, 2); // 입자가 낙하로 새지 않게 바닥 고정
      grid.set(0, 1, Material.prima.index);
      final portal = Portal.rects(
        gridWidth: 5,
        entryX: 0,
        entryY: 1,
        exitX: 4,
        exitY: 1,
        width: 1,
        height: 1,
      );
      Rules(DeterministicRng(1)).step(grid, portals: [portal]);
      expect(grid.get(0, 1), Material.empty.index);
      expect(grid.get(4, 1), Material.prima.index);
    });

    test('출구가 막혀 있으면 입구에서 대기한다', () {
      final grid = Grid(5, 3);
      _floor(grid, 2);
      grid.set(0, 1, Material.prima.index);
      grid.set(4, 1, Material.wall.index); // 출구 점유
      final portal = Portal.rects(
        gridWidth: 5,
        entryX: 0,
        entryY: 1,
        exitX: 4,
        exitY: 1,
        width: 1,
        height: 1,
      );
      Rules(DeterministicRng(1)).step(grid, portals: [portal]);
      expect(grid.get(0, 1), Material.prima.index); // 대기
    });

    test('한 틱에 한 번만 이동한다 (연쇄 텔레포트 방지)', () {
      // A(0,1)→B(2,1), B(2,1)→C(4,1). A의 입자는 한 틱에 B까지만 간다.
      final grid = Grid(5, 3);
      _floor(grid, 2);
      grid.set(0, 1, Material.prima.index);
      final ab = Portal.rects(
        gridWidth: 5,
        entryX: 0,
        entryY: 1,
        exitX: 2,
        exitY: 1,
        width: 1,
        height: 1,
      );
      final bc = Portal.rects(
        gridWidth: 5,
        entryX: 2,
        entryY: 1,
        exitX: 4,
        exitY: 1,
        width: 1,
        height: 1,
      );
      final rules = Rules(DeterministicRng(1));
      rules.step(grid, portals: [ab, bc]);
      expect(grid.get(2, 1), Material.prima.index); // B에서 멈춤
      expect(grid.get(4, 1), Material.empty.index); // C까지 가지 않음
      rules.step(grid, portals: [ab, bc]);
      expect(grid.get(4, 1), Material.prima.index); // 다음 틱에 C 도달
    });
  });

  group('온도 존 (GDD 6, 레벨 고정 화로/빙결)', () {
    test('화로 존이 룬 없이 존 안의 ICE를 녹여 WATER로 만든다', () {
      final grid = Grid(3, 3);
      grid.set(1, 1, Material.ice.index);
      final zone = TemperatureZone.rect(
        gridWidth: 3,
        x: 0,
        y: 0,
        width: 3,
        height: 3,
        kind: TemperatureZoneKind.heat,
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [zone]);
      }
      // ICE→WATER→STEAM까지 갈 수 있으나, 최소한 ICE는 사라졌다.
      expect(_count(grid, Material.ice), 0);
    });

    test('빙결 존이 존 안의 WATER를 얼려 ICE로 만든다', () {
      // 1x1: 물이 흘러나가지 못하게 가둬 상전이만 관찰한다.
      final grid = Grid(1, 1);
      grid.set(0, 0, Material.water.index);
      final zone = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.cool,
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [zone]);
      }
      expect(grid.get(0, 0), Material.ice.index); // WATER→ICE, ICE는 냉각 불변
    });

    test('존 밖의 물질은 영향받지 않는다', () {
      final grid = Grid(5, 1);
      grid.set(0, 0, Material.ice.index); // 존 안
      grid.set(4, 0, Material.ice.index); // 존 밖
      final zone = TemperatureZone.rect(
        gridWidth: 5,
        x: 0,
        y: 0,
        width: 2,
        height: 1,
        kind: TemperatureZoneKind.heat,
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [zone]);
      }
      expect(grid.get(4, 0), Material.ice.index); // 존 밖 ICE 불변
    });

    test('전이 불가 물질만 있으면 RNG를 소비하지 않는다 (결정성 계약)', () {
      // 존 안에 벽만 → 전이 대상 없음 → RNG 상태 불변. 이후 같은 입력이 동일 결과.
      final probe = DeterministicRng(1);
      final grid = Grid(3, 3);
      grid.set(1, 1, Material.wall.index);
      final zone = TemperatureZone.rect(
        gridWidth: 3,
        x: 0,
        y: 0,
        width: 3,
        height: 3,
        kind: TemperatureZoneKind.heat,
      );
      Rules(probe).step(grid, zones: [zone]);
      // 벽/EMPTY만 있었으므로 RNG는 그대로 첫 값을 낸다.
      expect(probe.nextUint32(), DeterministicRng(1).nextUint32());
    });

    test('probability 재정의가 전이 속도를 바꾼다 (0이면 전이 없음)', () {
      final grid = Grid(1, 1);
      grid.set(0, 0, Material.ice.index);
      final zone = TemperatureZone.rect(
        gridWidth: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        kind: TemperatureZoneKind.heat,
        probability: 0.0, // 강도 0 → 절대 전이하지 않음
      );
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 100; i++) {
        rules.step(grid, zones: [zone]);
      }
      expect(grid.get(0, 0), Material.ice.index); // 그대로 (녹지 않음)
    });
  });

  group('재/순수 (GDD 6, ashRatio 선반영 확인)', () {
    test('ASH는 입자로 낙하·퇴적한다', () {
      final grid = Grid(3, 9);
      _floor(grid, 8);
      grid.set(1, 0, Material.ash.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 12; i++) {
        rules.step(grid);
      }
      expect(grid.get(1, 7), Material.ash.index); // 바닥 위에 쌓임
    });

    test('ASH는 가열·냉각에 불변 (오염원)', () {
      final grid = Grid(3, 3);
      grid.set(1, 1, Material.ash.index);
      grid.set(1, 0, Material.heatLine.index);
      grid.set(1, 2, Material.coldLine.index);
      final rules = Rules(DeterministicRng(1));
      for (var i = 0; i < 50; i++) {
        rules.step(grid);
      }
      expect(_count(grid, Material.ash), 1); // 상전이 없음
    });
  });
}
