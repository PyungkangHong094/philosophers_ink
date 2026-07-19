import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/level_session.dart';
import 'package:philosophers_ink/level/level_model.dart';

/// 상단 방출구(열 5~7)가 물질을 흘리고, 그 아래 개방형 비커를 둔 테스트 레벨.
/// 비커 rect (4,3,5,8): 좌벽 col4·우벽 col8·바닥 row10, 상단(row3) 개방, 내부 cols5~7.
/// 방출구 열이 비커 내부 열과 정렬돼 물질이 입구로 낙하한다.
Level _level({
  int goal = 5,
  bool pure = false,
  Material emit = Material.prima,
  Map<InkType, int>? optimal,
  List<TerrainRect> terrain = const [],
  FlaskMouth mouth = FlaskMouth.up,
  int difficulty = 1,
  int? timeLimitSeconds,
}) =>
    Level(
      meta: LevelMeta(
          id: 1,
          name: 't',
          chapter: 1,
          difficulty: difficulty,
          optimalInk: optimal),
      background: 0xFF000000,
      emitters: [EmitterSpec(x: 5, y: 0, width: 3, material: emit, rate: 1)],
      flasks: [FlaskSpec(x: 4, y: 3, w: 5, h: 8, goal: goal, pure: pure, mouth: mouth)],
      terrain: terrain,
      inkBudget: const {InkType.chalk: 100},
      timeLimitSeconds: timeLimitSeconds,
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

  group('개방형 비커 벽 (GDD 5.1 입구 규칙)', () {
    test('좌·우·바닥이 벽으로 스탬프되고 윗변(입구)은 개방', () {
      final s = LevelSession(_level());
      final g = s.game.grid;
      // 비커 rect (4,3,5,8): 좌 col4, 우 col8, 바닥 row10.
      for (var yy = 3; yy <= 10; yy++) {
        expect(g.get(4, yy), Material.wall.index, reason: '좌벽 col4');
        expect(g.get(8, yy), Material.wall.index, reason: '우벽 col8');
      }
      for (var xx = 4; xx <= 8; xx++) {
        expect(g.get(xx, 10), Material.wall.index, reason: '바닥 row10');
      }
      // 상단 입구(row3) 내부 열은 개방.
      for (var xx = 5; xx <= 7; xx++) {
        expect(g.get(xx, 3), Material.empty.index, reason: '입구 개방 col$xx');
      }
    });

    test('reset 후에도 비커 벽이 재스탬프된다', () {
      final s = LevelSession(_level());
      s.reset();
      final g = s.game.grid;
      expect(g.get(4, 6), Material.wall.index);
      expect(g.get(8, 6), Material.wall.index);
      expect(g.get(6, 10), Material.wall.index);
    });

    test('입구로 낙하한 물질이 내부에 착수해 카운트되고 클리어된다', () {
      final s = LevelSession(_level(goal: 5));
      _tickN(s, 60);
      expect(s.flasks.flasks.single.count, 5);
      expect(s.isCleared, isTrue);
    });

    test('물질 흐름이 비커 벽을 뚫거나 지우지 못한다 (측면·바닥 차단)', () {
      final s = LevelSession(_level(goal: 5));
      _tickN(s, 60);
      final g = s.game.grid;
      expect(g.get(4, 9), Material.wall.index, reason: '좌벽 유지');
      expect(g.get(8, 9), Material.wall.index, reason: '우벽 유지');
      expect(g.get(6, 10), Material.wall.index, reason: '바닥 유지');
    });

    test('벽 바깥(rect 밖) 물질은 판정 대상이 아니다', () {
      final s = LevelSession(_level(goal: 100)); // 클리어 방지
      final g = s.game.grid;
      // 좌벽(col4) 바로 왼쪽(col3)은 rect 밖 — 판정 스캔에 포함되지 않는다.
      g.set(3, 9, Material.water.index);
      s.flasks.update(g);
      expect(s.flasks.flasks.single.count, 0, reason: 'rect 밖 물질 미카운트');
      expect(g.get(3, 9), Material.water.index, reason: '소비도 안 됨');
    });

    test('mouth:down은 좌·우·윗변을 벽으로, 바닥을 개방한다 (천장 부착 ∩자)', () {
      final s = LevelSession(_level(mouth: FlaskMouth.down));
      final g = s.game.grid;
      // rect (4,3,5,8): 좌 col4, 우 col8, 윗변 row3(뚜껑), 바닥 row10(개방).
      for (var yy = 3; yy <= 10; yy++) {
        expect(g.get(4, yy), Material.wall.index, reason: '좌벽');
        expect(g.get(8, yy), Material.wall.index, reason: '우벽');
      }
      for (var xx = 4; xx <= 8; xx++) {
        expect(g.get(xx, 3), Material.wall.index, reason: '윗변 뚜껑');
      }
      // 바닥(row10) 내부 열은 개방.
      for (var xx = 5; xx <= 7; xx++) {
        expect(g.get(xx, 10), Material.empty.index, reason: '바닥 개방 col$xx');
      }
    });

    test('mouth:down 내부 물질은 카운트, 뚜껑(윗변)은 벽이라 미카운트', () {
      final s = LevelSession(_level(mouth: FlaskMouth.down, goal: 10));
      final g = s.game.grid;
      g.set(6, 9, Material.water.index); // 내부(개방 바닥 근처)
      s.flasks.update(g);
      expect(s.flasks.flasks.single.count, 1, reason: '내부 동적 물질 카운트');
      expect(g.get(6, 3), Material.wall.index, reason: '윗변은 뚜껑 벽');
    });

    test('mouth:down + 반전 중력: 상승 물질이 아래 입구로 진입해 카운트된다', () {
      // 천장 부착 비커(∩자) + 중력 반전 기믹. 반전 시 입자는 위로 상승한다.
      final level = Level(
        meta: LevelMeta(id: 1, name: 't', chapter: 1, difficulty: 1),
        background: 0xFF000000,
        emitters: [
          EmitterSpec(x: 5, y: 0, width: 3, material: Material.prima, rate: 1),
        ],
        flasks: [
          FlaskSpec(x: 4, y: 3, w: 5, h: 8, goal: 3, mouth: FlaskMouth.down),
        ],
        gimmicks: const [GimmickSpec(type: GimmickType.gravityFlip)],
        inkBudget: const {InkType.chalk: 0},
      );
      final s = LevelSession(level);
      expect(s.hasGravityFlip, isTrue);
      s.setGravityInverted(true);
      // 아래 입구(바닥 row10) 밑에 물질을 놓는다 — 반전 중력에서 위로 상승해 입구로 진입.
      for (var xx = 5; xx <= 7; xx++) {
        s.game.grid.set(xx, 20, Material.prima.index);
      }
      _tickN(s, 40);
      expect(s.flasks.flasks.single.count, 3,
          reason: '상승 물질이 아래 입구로 진입·카운트');
      expect(s.isCleared, isTrue);
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

  group('제한 시간 카운트다운 (GDD 2장)', () {
    test('기본값이 난이도 밴드에서 파생된다 (×60틱/s)', () {
      // D1–2 80s, D3–4 180s, D5–6 360s, D7–8 720s, D9–10 1440s.
      expect(LevelSession(_level(difficulty: 1)).timeLimitTicks, 80 * 60);
      expect(LevelSession(_level(difficulty: 4)).timeLimitTicks, 180 * 60);
      expect(LevelSession(_level(difficulty: 5)).timeLimitTicks, 360 * 60);
      expect(LevelSession(_level(difficulty: 8)).timeLimitTicks, 720 * 60);
      expect(LevelSession(_level(difficulty: 10)).timeLimitTicks, 1440 * 60);
    });

    test('JSON time_limit_s가 밴드 기본값을 재정의한다', () {
      final s = LevelSession(_level(difficulty: 1, timeLimitSeconds: 10));
      expect(s.timeLimitTicks, 10 * 60, reason: '80s 기본값 대신 10s');
    });

    test('한도 도달 + 미클리어 → timeout 실패', () {
      // 1초(60틱) 한도, 큰 goal로 미클리어 유지.
      final s = LevelSession(_level(goal: 100000, timeLimitSeconds: 1));
      for (var i = 0; i < 70; i++) {
        s.tick();
      }
      expect(s.isFailed, isTrue);
      expect(s.isTimedOut, isTrue);
      expect(s.failureReason, LevelFailure.timeout);
      expect(s.remainingTicks, 0);
    });

    test('한도 전에 클리어하면 이후 시간 초과해도 실패 아님', () {
      final s = LevelSession(_level(goal: 3, timeLimitSeconds: 1));
      for (var i = 0; i < 70; i++) {
        s.tick();
      }
      expect(s.isCleared, isTrue);
      expect(s.isTimedOut, isFalse, reason: '클리어 후 timeout 미발동');
      expect(s.isFailed, isFalse);
      expect(s.failureReason, isNull);
    });

    test('오염이 시간 초과보다 우선한다', () {
      // 오염 + 시간 초과 동시: contamination 사유.
      final s = LevelSession(
          _level(goal: 100000, pure: true, emit: Material.ash, timeLimitSeconds: 1));
      for (var i = 0; i < 70; i++) {
        s.tick();
      }
      expect(s.isFailed, isTrue);
      expect(s.failureReason, LevelFailure.contamination);
    });

    test('reset이 시간을 복원한다', () {
      final s = LevelSession(_level(goal: 100000, timeLimitSeconds: 1));
      for (var i = 0; i < 70; i++) {
        s.tick();
      }
      expect(s.isTimedOut, isTrue);
      s.reset();
      expect(s.isTimedOut, isFalse);
      expect(s.isFailed, isFalse);
      expect(s.remainingTicks, s.timeLimitTicks);
    });
  });

  group('dispose (notifier 정리)', () {
    test('dispose가 소유 notifier(InkController)를 정리한다', () {
      final s = LevelSession(_level());
      // 폐기 전에는 리스너 등록·해제가 정상.
      void listener() {}
      s.ink.addListener(listener);
      s.ink.removeListener(listener);

      s.dispose();

      // 폐기 후 InkController 사용 시 ChangeNotifier가 assert로 막는다(리스너 누수 방지).
      expect(() => s.ink.addListener(() {}), throwsA(isA<FlutterError>()));
    });

    test('dispose는 예외 없이 완료된다', () {
      final s = LevelSession(_level());
      expect(s.dispose, returnsNormally);
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
