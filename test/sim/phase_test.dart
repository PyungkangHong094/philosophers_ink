import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/sim/materials.dart';

// 상태 플라스크(물방울/눈꽃/김) 판정 기반 — 상 매핑 (GDD 5.1).
void main() {
  test('phaseOf: 액체/고체/기체 매핑', () {
    expect(phaseOf(Material.water.index), Phase.liquid);
    expect(phaseOf(Material.lava.index), Phase.liquid);
    expect(phaseOf(Material.steam.index), Phase.gas);
    expect(phaseOf(Material.ice.index), Phase.solid);
    expect(phaseOf(Material.prima.index), Phase.solid);
    expect(phaseOf(Material.ash.index), Phase.solid);
    expect(phaseOf(Material.stone.index), Phase.solid);
  });

  test('phaseOf: EMPTY·정적(벽/룬선)은 null', () {
    expect(phaseOf(Material.empty.index), isNull);
    expect(phaseOf(Material.wall.index), isNull);
    expect(phaseOf(Material.heatLine.index), isNull);
    expect(phaseOf(Material.coldLine.index), isNull);
  });
}
