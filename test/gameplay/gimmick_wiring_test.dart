import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/level_session.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';

/// 기믹(변성 게이트·포탈·온도 존·중력반전·재)을 배치한 챕터3 레벨.
Level gimmickLevel({bool withGravityFlip = true}) {
  final gimmicks = <Map<String, dynamic>>[
    {
      'type': 'variance_gate',
      'params': {'x': 0, 'y': 160, 'w': 160, 'h': 1, 'to': 'WATER', 'from': 'PRIMA'},
    },
    {
      'type': 'portal',
      'params': {
        'entry': {'x': 4, 'y': 290, 'w': 5, 'h': 5},
        'exit': {'x': 150, 'y': 8, 'w': 5, 'h': 5},
      },
    },
    {
      'type': 'temp_zone',
      'params': {'x': 0, 'y': 4, 'w': 160, 'h': 20, 'kind': 'cool', 'probability': null},
    },
    if (withGravityFlip) {'type': 'gravity_flip', 'params': <String, dynamic>{}},
  ];
  final map = {
    'meta': {
      'id': 36,
      'name': '기믹 배선',
      'chapter': 3,
      'difficulty': 6,
      'teaches': <String>[],
      'tags': <String>[],
      'optimal_ink': {'chalk': 80},
      'solutions_verified': 2,
      'hint_stroke': null,
    },
    'background': '#1D1418',
    'emitters': [
      {'x': 74, 'y': 2, 'width': 13, 'material': 'WATER', 'rate': 2, 'total': null, 'ash_ratio': 0.3},
    ],
    'flasks': [
      {'x': 70, 'y': 300, 'w': 20, 'h': 18, 'goal': 25, 'material': null, 'state': null, 'pure': false},
    ],
    'terrain': <dynamic>[],
    'gimmicks': gimmicks,
    'ink_budget': {'chalk': 100, 'heat': 0, 'frost': 0},
    'star_thresholds': null,
  };
  return loadLevelFromJson(jsonEncode(map));
}

void main() {
  group('LevelSession 기믹 배선', () {
    test('게이트·포탈·온도 존이 GameState에 주입된다', () {
      final s = LevelSession(gimmickLevel());
      expect(s.game.gates.length, 1);
      expect(s.game.portals.length, 1);
      expect(s.game.temperatureZones.length, 1);
    });

    test('중력 반전 기믹이 있으면 hasGravityFlip true', () {
      expect(LevelSession(gimmickLevel()).hasGravityFlip, isTrue);
      expect(LevelSession(gimmickLevel(withGravityFlip: false)).hasGravityFlip,
          isFalse);
    });
  });

  group('중력 반전 입력 로그 (결정성 계약)', () {
    test('토글이 로그에 (틱, 값)으로 기록된다', () {
      final s = LevelSession(gimmickLevel());
      for (var i = 0; i < 30; i++) {
        s.tick();
      }
      s.setGravityInverted(true);
      expect(s.gravityInverted, isTrue);
      expect(s.gravityLog.length, 1);
      expect(s.gravityLog.single.tick, 30);
      expect(s.gravityLog.single.inverted, isTrue);
    });

    test('같은 값 재설정은 로그를 늘리지 않는다', () {
      final s = LevelSession(gimmickLevel());
      s.setGravityInverted(true);
      s.setGravityInverted(true);
      expect(s.gravityLog.length, 1);
    });

    test('기믹 없는 레벨에서는 토글이 무시된다', () {
      final s = LevelSession(gimmickLevel(withGravityFlip: false));
      s.setGravityInverted(true);
      expect(s.gravityInverted, isFalse);
      expect(s.gravityLog, isEmpty);
    });

    test('reset이 로그와 중력을 초기화한다', () {
      final s = LevelSession(gimmickLevel());
      s.setGravityInverted(true);
      s.reset();
      expect(s.gravityLog, isEmpty);
      expect(s.gravityInverted, isFalse);
    });
  });

  group('기믹 + 중력 토글 결정성 (재시작 3회 동일)', () {
    int runAndHash() {
      final s = LevelSession(gimmickLevel());
      // 결정적 입력: 벽 하나 + 중력 반전(틱 40 on, 틱 90 off).
      final stroke = s.game.beginStroke(InkType.chalk);
      s.game.extendStroke(stroke, 40, 250, 120, 250);
      for (var t = 0; t < 140; t++) {
        if (t == 40) s.setGravityInverted(true);
        if (t == 90) s.setGravityInverted(false);
        s.tick();
      }
      return s.game.grid.hash();
    }

    test('3회 동일 해시', () {
      final h1 = runAndHash();
      final h2 = runAndHash();
      final h3 = runAndHash();
      expect(h2, h1);
      expect(h3, h1);
    });

    test('reset 후 재생도 동일 해시', () {
      final s = LevelSession(gimmickLevel());
      int playOnce() {
        final stroke = s.game.beginStroke(InkType.chalk);
        s.game.extendStroke(stroke, 40, 250, 120, 250);
        for (var t = 0; t < 140; t++) {
          if (t == 40) s.setGravityInverted(true);
          if (t == 90) s.setGravityInverted(false);
          s.tick();
        }
        return s.game.grid.hash();
      }

      final first = playOnce();
      s.reset();
      final second = playOnce();
      expect(second, first);
    });
  });
}
