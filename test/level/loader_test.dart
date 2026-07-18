import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_exception.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';

/// 챕터 2, 상태 플라스크를 쓰는 유효 레벨 맵(변형해 불량 케이스 생성).
Map<String, dynamic> validLevelMap() => {
      'meta': {
        'id': 21,
        'name': '테스트',
        'chapter': 2,
        'difficulty': 4,
        'teaches': <String>[],
        'tags': <String>[],
        'optimal_ink': {'chalk': 60, 'frost': 40},
        'solutions_verified': 2,
        'hint_stroke': null,
      },
      'background': '#E9E5DB',
      'emitters': [
        {'x': 80, 'y': 2, 'material': 'WATER', 'rate': 1, 'total': null, 'ash_ratio': 0},
      ],
      'flasks': [
        {'x': 70, 'y': 280, 'w': 20, 'h': 18, 'goal': 25, 'material': null, 'state': 'solid', 'pure': false},
      ],
      'terrain': <dynamic>[],
      'gimmicks': <dynamic>[],
      'ink_budget': {'chalk': 80, 'heat': 0, 'frost': 60},
      'star_thresholds': null,
    };

String jsonOf(Map<String, dynamic> m) => jsonEncode(m);

void main() {
  group('정상 파싱', () {
    test('유효 레벨의 필드가 모델에 그대로 매핑된다', () {
      final level = loadLevelFromJson(jsonOf(validLevelMap()));
      expect(level.meta.id, 21);
      expect(level.meta.chapter, 2);
      expect(level.background, 0xFFE9E5DB);
      expect(level.emitters.single.material, Material.water);
      expect(level.flasks.single.state, FlaskState.solid);
      expect(level.flasks.single.goal, 25);
      expect(level.inkBudget[InkType.frost], 60);
      expect(level.meta.optimalInk![InkType.chalk], 60);
      expect(level.meta.optimalTotal, 100);
      expect(level.starThresholds, isNull);
    });

    test('#RRGGBB는 불투명 알파를 채운다', () {
      final m = validLevelMap();
      m['background'] = '#123456';
      final level = loadLevelFromJson(jsonOf(m));
      expect(level.background, 0xFF123456);
    });
  });

  group('실제 에셋 픽스처 (콘텐츠 갱신에 견고한 스모크)', () {
    // 출고 레벨은 콘텐츠라 값이 계속 바뀐다 — 특정 필드 단언 대신 "모든 레벨 JSON이
    // 로더 검증을 통과한다"로만 확인한다. 필드 매핑 단언은 인라인 픽스처(validLevelMap)가 담당.
    test('assets/levels/의 모든 레벨 JSON이 로더 검증을 통과한다', () {
      final files = Directory('assets/levels')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty, reason: '출고 레벨 JSON이 최소 1개 있어야 한다');
      for (final f in files) {
        final text = f.readAsStringSync();
        expect(
          () => loadLevelFromJson(text, source: f.path),
          returnsNormally,
          reason: '${f.path} 로드·검증 실패',
        );
      }
    });
  });

  group('명시적 에러 (조용한 스킵 금지)', () {
    test('JSON이 아니면 예외', () {
      expect(
        () => loadLevelFromJson('{ this is not json'),
        throwsA(isA<LevelException>()),
      );
    });

    test('최상위가 객체가 아니면 예외', () {
      expect(() => loadLevelFromJson('[]'), throwsA(isA<LevelException>()));
    });

    test('플라스크 좌표가 그리드 밖이면 예외', () {
      final m = validLevelMap();
      (m['flasks'] as List)[0]['x'] = 9999;
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('그리드')))),
      );
    });

    test('방출구 물질이 정적이면(WALL) 예외', () {
      final m = validLevelMap();
      (m['emitters'] as List)[0]['material'] = 'WALL';
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('방출 불가')))),
      );
    });

    test('알 수 없는 물질명이면 예외', () {
      final m = validLevelMap();
      (m['emitters'] as List)[0]['material'] = 'PLASMA';
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('알 수 없는 물질')))),
      );
    });

    test('해금 정합성 — 챕터1에 서리 예산 지급 시 예외', () {
      final m = validLevelMap();
      m['meta']['chapter'] = 1;
      m['meta']['optimal_ink'] = {'chalk': 40};
      m['flasks'][0]['state'] = null; // 상태 플라스크도 챕터1 위반이므로 제거
      m['emitters'][0]['material'] = 'PRIMA'; // WATER도 챕터2 → PRIMA로
      m['ink_budget'] = {'chalk': 80, 'heat': 0, 'frost': 60}; // frost>0 위반
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException &&
            e.problems.any((p) => p.contains('frost') && p.contains('해금')))),
      );
    });

    test('해금 정합성 — 챕터1에 상태 플라스크 예외', () {
      final m = validLevelMap();
      m['meta']['chapter'] = 1;
      m['meta']['optimal_ink'] = {'chalk': 40};
      m['emitters'][0]['material'] = 'PRIMA';
      m['ink_budget'] = {'chalk': 80, 'heat': 0, 'frost': 0};
      // 상태 플라스크는 그대로 → 위반.
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException &&
            e.problems.any((p) => p.contains('상태 플라스크')))),
      );
    });

    test('순수 플라스크는 챕터3부터 — 챕터2에서 예외', () {
      final m = validLevelMap();
      m['flasks'][0]['pure'] = true;
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('순수')))),
      );
    });

    test('알 수 없는 기믹 type이면 예외', () {
      final m = validLevelMap();
      m['gimmicks'] = [
        {'type': 'teleport_ray', 'params': <String, dynamic>{}},
      ];
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException &&
            e.problems.any((p) => p.contains('알 수 없는 기믹')))),
      );
    });

    test('여러 위반을 한 번에 모아 보고', () {
      final m = validLevelMap();
      (m['flasks'] as List)[0]['x'] = 9999; // 좌표 밖
      (m['flasks'] as List)[0]['goal'] = 0; // goal 위반
      try {
        loadLevelFromJson(jsonOf(m));
        fail('예외가 나야 한다');
      } on LevelException catch (e) {
        expect(e.problems.length, greaterThanOrEqualTo(2));
      }
    });
  });
}
