import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_exception.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/serializer.dart';

/// 챕터 1, 석필만 쓰는 유효 레벨 맵(hint_stroke 변형용).
/// hint_stroke는 힌트 스트로크 객체 배열 `[{ink,x0,y0,x1,y1},...]` (모델 HintStroke).
Map<String, dynamic> validLevelMap() => {
      'meta': {
        'id': 1,
        'name': '첫 획',
        'chapter': 1,
        'difficulty': 1,
        'teaches': <String>[],
        'tags': <String>[],
        'optimal_ink': null,
        'solutions_verified': 2,
        'hint_stroke': null,
      },
      'background': '#1D1418',
      'emitters': [
        {'x': 18, 'y': 2, 'width': 4, 'material': 'PRIMA', 'rate': 5, 'total': null, 'ash_ratio': 0},
      ],
      'flasks': [
        {'x': 108, 'y': 290, 'w': 20, 'h': 18, 'goal': 25, 'material': null, 'state': null, 'pure': false},
      ],
      'terrain': <dynamic>[],
      'gimmicks': <dynamic>[],
      'ink_budget': {'chalk': 720, 'heat': 0, 'frost': 0},
      'star_thresholds': null,
    };

String jsonOf(Map<String, dynamic> m) => jsonEncode(m);

void main() {
  group('hint_stroke 파싱', () {
    test('null이면 hintStroke는 null', () {
      final level = loadLevelFromJson(jsonOf(validLevelMap()));
      expect(level.meta.hintStroke, isNull);
    });

    test('객체 배열이 잉크·좌표로 파싱된다', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = [
        {'ink': 'chalk', 'x0': 19, 'y0': 181, 'x1': 107, 'y1': 270},
      ];
      final level = loadLevelFromJson(jsonOf(m));
      final hints = level.meta.hintStroke!;
      expect(hints, hasLength(1));
      expect(hints.first.ink, InkType.chalk);
      expect(hints.first.x0, 19);
      expect(hints.first.y0, 181);
      expect(hints.first.x1, 107);
      expect(hints.first.y1, 270);
    });
  });

  group('hint_stroke 검증', () {
    test('알 수 없는 잉크는 명시적 에러', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = [
        {'ink': 'plasma', 'x0': 1, 'y0': 1, 'x1': 2, 'y1': 2},
      ];
      expect(() => loadLevelFromJson(jsonOf(m)),
          throwsA(isA<LevelException>()));
    });

    test('그리드 밖 좌표는 거부된다', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = [
        {'ink': 'chalk', 'x0': 19, 'y0': 181, 'x1': 999, 'y1': 270},
      ];
      expect(() => loadLevelFromJson(jsonOf(m)),
          throwsA(isA<LevelException>()));
    });

    test('빈 배열은 거부된다(힌트 없음은 null이어야)', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = <dynamic>[];
      expect(() => loadLevelFromJson(jsonOf(m)),
          throwsA(isA<LevelException>()));
    });

    test('미해금 잉크 힌트는 거부된다(챕터 1에 frost)', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = [
        {'ink': 'frost', 'x0': 10, 'y0': 10, 'x1': 20, 'y1': 20},
      ];
      expect(() => loadLevelFromJson(jsonOf(m)),
          throwsA(isA<LevelException>()));
    });
  });

  group('직렬화 왕복', () {
    test('hintStroke가 serializeLevel→load 왕복에서 무손실', () {
      final m = validLevelMap();
      m['meta']['hint_stroke'] = [
        {'ink': 'chalk', 'x0': 19, 'y0': 181, 'x1': 107, 'y1': 270},
      ];
      final level = loadLevelFromJson(jsonOf(m));
      final round = loadLevelFromJson(serializeLevel(level));
      expect(round.meta.hintStroke, equals(level.meta.hintStroke));
    });

    test('null hintStroke도 왕복 보존', () {
      final level = loadLevelFromJson(jsonOf(validLevelMap()));
      final round = loadLevelFromJson(serializeLevel(level));
      expect(round.meta.hintStroke, isNull);
    });

    test('HintStroke.toJson/fromJson 왕복', () {
      const s = HintStroke(ink: InkType.chalk, x0: 1, y0: 2, x1: 3, y1: 4);
      expect(HintStroke.fromJson(s.toJson()), equals(s));
    });
  });
}
