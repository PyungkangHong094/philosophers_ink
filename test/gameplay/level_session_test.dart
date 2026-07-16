import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/level_session.dart';
import 'package:philosophers_ink/level/level_model.dart';

/// 상단 방출구가 열 5로 물질을 흘리고, 열 5·행 8에 1×1 플라스크를 둔 테스트 레벨.
Level _level({
  int goal = 5,
  bool pure = false,
  Material emit = Material.prima,
  Map<InkType, int>? optimal,
  List<TerrainRect> terrain = const [],
}) =>
    Level(
      meta: LevelMeta(
          id: 1, name: 't', chapter: 1, difficulty: 1, optimalInk: optimal),
      background: 0xFF000000,
      emitters: [EmitterSpec(x: 5, y: 0, material: emit, rate: 1)],
      flasks: [FlaskSpec(x: 5, y: 8, w: 1, h: 1, goal: goal, pure: pure)],
      terrain: terrain,
      inkBudget: const {InkType.chalk: 100},
    );

void _tickN(LevelSession s, int n) {
  for (var i = 0; i < n; i++) {
    s.tick();
  }
}

void main() {
  group('방출 → 낙하 → 착수 카운트 → 클리어', () {
    test('흘린 물질이 플라스크에 착수해 목표까지 카운트되면 클리어', () {
      final s = LevelSession(_level(goal: 5));
      expect(s.isCleared, isFalse);
      _tickN(s, 40);
      expect(s.flasks.flasks.single.count, 5);
      expect(s.isCleared, isTrue);
    });
  });

  group('잉크 예산 주입', () {
    test('레벨 ink_budget이 세션 예산으로', () {
      final s = LevelSession(_level());
      expect(s.ink.budget.initial(InkType.chalk), 100);
      expect(s.ink.budget.isHidden(InkType.heat), isTrue);
      expect(s.ink.budget.isHidden(InkType.frost), isTrue);
    });
  });

  group('순수 오염 실패', () {
    test('재(ASH)가 순수 플라스크에 착수하면 실패', () {
      final s = LevelSession(_level(goal: 5, pure: true, emit: Material.ash));
      _tickN(s, 20);
      expect(s.isFailed, isTrue);
      expect(s.isCleared, isFalse);
    });
  });

  group('별점', () {
    test('잉크 0 사용 클리어 → 최적해 대비 3성', () {
      final s = LevelSession(_level(goal: 5, optimal: const {InkType.chalk: 20}));
      _tickN(s, 40);
      expect(s.isCleared, isTrue);
      expect(s.result.stars, 3, reason: '사용 0 ≤ floor(20*1.15)=23');
    });
  });

  group('지형 스탬프', () {
    test('지형이 그리드에 벽으로 스탬프되고 reset 후 재스탬프', () {
      final terrain = [
        const TerrainRect(x: 20, y: 20, w: 4, h: 2, material: Material.wall),
      ];
      final s = LevelSession(_level(terrain: terrain));
      expect(s.game.grid.get(20, 20), Material.wall.index);
      expect(s.game.grid.get(23, 21), Material.wall.index);
      s.reset();
      expect(s.game.grid.get(20, 20), Material.wall.index, reason: 'reset 후 재스탬프');
    });
  });

  group('재시작 결정성 (GDD 10.5)', () {
    test('3회 연속 재시작 — 같은 틱 수 후 그리드 해시·카운트 동일', () {
      final s = LevelSession(_level(goal: 5));
      List<int> runOnce() {
        s.reset();
        _tickN(s, 30);
        return [s.game.grid.hash(), s.flasks.flasks.single.count];
      }

      final r1 = runOnce();
      final r2 = runOnce();
      final r3 = runOnce();
      expect(r2, r1);
      expect(r3, r1);
    });
  });
}
