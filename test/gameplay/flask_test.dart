import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/flask.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/sim/grid.dart';

Grid _grid() => Grid(10, 10);

/// 영역 (x..x+w, y..y+h)를 물질로 채운다.
void _fill(Grid g, int x, int y, int w, int h, Material m) {
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      g.set(xx, yy, m.index);
    }
  }
}

int _countMaterial(Grid g, Material m) {
  var n = 0;
  for (final c in g.cells) {
    if (c == m.index) n++;
  }
  return n;
}

void main() {
  group('무조건 플라스크', () {
    test('어떤 물질이든 카운트하고 소비한다', () {
      final g = _grid();
      _fill(g, 2, 2, 2, 2, Material.prima); // 4셀
      final sys = FlaskSystem(const [
        FlaskSpec(x: 2, y: 2, w: 2, h: 2, goal: 10),
      ]);
      sys.update(g);
      expect(sys.flasks.single.count, 4);
      expect(_countMaterial(g, Material.prima), 0, reason: '소비됨');
    });

    test('goal 도달 시 완료, 초과 물질도 소비하되 카운트는 상한', () {
      final g = _grid();
      _fill(g, 0, 0, 3, 3, Material.prima); // 9셀
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 3, h: 3, goal: 5),
      ]);
      sys.update(g);
      expect(sys.flasks.single.count, 5, reason: 'goal에서 카운트 멈춤');
      expect(sys.flasks.single.isComplete, isTrue);
      expect(_countMaterial(g, Material.prima), 0, reason: '초과분도 소비');
    });
  });

  group('물질 지정 플라스크', () {
    test('지정 물질만 카운트, 타 물질은 통과·소멸', () {
      final g = _grid();
      g.set(1, 1, Material.water.index);
      g.set(2, 1, Material.prima.index); // 타 물질
      g.set(3, 1, Material.water.index);
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 5, h: 5, goal: 10, material: Material.water),
      ]);
      sys.update(g);
      expect(sys.flasks.single.count, 2, reason: 'WATER 2개만');
      expect(_countMaterial(g, Material.water), 0);
      expect(_countMaterial(g, Material.prima), 0, reason: '타 물질도 소멸');
    });
  });

  group('상태 지정 플라스크', () {
    test('고체 조건 — 얼음은 카운트, 물(액체)은 소멸', () {
      final g = _grid();
      g.set(1, 1, Material.ice.index); // 입자=고체
      g.set(2, 1, Material.water.index); // 액체 (비매칭)
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 5, h: 5, goal: 10, state: FlaskState.solid),
      ]);
      sys.update(g);
      expect(sys.flasks.single.count, 1, reason: '얼음만');
      expect(_countMaterial(g, Material.ice), 0);
      // 물은 액체라 상태 비매칭 → 남긴다 (전이 유도).
      expect(_countMaterial(g, Material.water), 1, reason: '비매칭 상은 소비 안 함');
    });

    test('액체 조건 — 증기는 남겨 응결을 기다리고, 물은 카운트', () {
      final g = _grid();
      g.set(1, 1, Material.steam.index); // 기체 (비매칭) → 남김
      final liq = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 5, h: 5, goal: 10, state: FlaskState.liquid),
      ]);
      liq.update(g);
      expect(liq.flasks.single.count, 0);
      expect(_countMaterial(g, Material.steam), 1, reason: '증기는 그 자리에 남아 응결 대기');

      // 다음 틱: 증기가 물로 전이했다고 가정.
      g.set(1, 1, Material.water.index);
      liq.update(g);
      expect(liq.flasks.single.count, 1, reason: '응결한 물이 카운트');
      expect(_countMaterial(g, Material.water), 0);
    });
  });

  group('순수(❗) 플라스크', () {
    test('ASH 혼입 시 오염 + 실패, 재는 제거', () {
      final g = _grid();
      g.set(1, 1, Material.water.index);
      g.set(2, 1, Material.ash.index);
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 5, h: 5, goal: 10, material: Material.water, pure: true),
      ]);
      sys.update(g);
      expect(sys.flasks.single.contaminated, isTrue);
      expect(sys.isFailed, isTrue);
      expect(sys.isCleared, isFalse, reason: '오염되면 클리어 불가');
      expect(_countMaterial(g, Material.ash), 0, reason: '재 제거');
      expect(sys.flasks.single.count, 1, reason: 'WATER는 정상 카운트');
    });
  });

  group('클리어·실패·리셋', () {
    test('모든 플라스크 목표 충족 시 클리어', () {
      final g = _grid();
      g.set(0, 0, Material.water.index);
      g.set(5, 5, Material.prima.index);
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 1, h: 1, goal: 1, material: Material.water),
        FlaskSpec(x: 5, y: 5, w: 1, h: 1, goal: 1),
      ]);
      expect(sys.isCleared, isFalse);
      sys.update(g);
      expect(sys.isCleared, isTrue);
    });

    test('reset은 카운트·오염을 되돌린다', () {
      final g = _grid();
      _fill(g, 0, 0, 2, 2, Material.ash);
      final sys = FlaskSystem(const [
        FlaskSpec(x: 0, y: 0, w: 2, h: 2, goal: 2, pure: true),
      ]);
      sys.update(g);
      expect(sys.flasks.single.count > 0 || sys.isFailed, isTrue);
      sys.reset();
      expect(sys.flasks.single.count, 0);
      expect(sys.flasks.single.contaminated, isFalse);
      expect(sys.isFailed, isFalse);
    });
  });

  group('착수 이벤트', () {
    test('카운트마다 onSettle 발행 (좌표·물질·상)', () {
      final g = _grid();
      g.set(3, 4, Material.ice.index);
      final events = <SettleEvent>[];
      final sys = FlaskSystem(
        const [FlaskSpec(x: 0, y: 0, w: 6, h: 6, goal: 10, state: FlaskState.solid)],
        onSettle: events.add,
      );
      sys.update(g);
      expect(events.length, 1);
      expect(events.single.x, 3);
      expect(events.single.y, 4);
      expect(events.single.material, Material.ice);
      expect(events.single.phase, FlaskState.solid);
    });
  });
}
