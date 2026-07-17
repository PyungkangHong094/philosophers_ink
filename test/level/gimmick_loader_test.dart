import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/level/gimmick_builder.dart';
import 'package:philosophers_ink/level/level_exception.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/serializer.dart';
import 'package:philosophers_ink/sim/gimmicks.dart';

/// 챕터 3 유효 레벨(기믹 5종 전부 배치) — 변형해 불량 케이스를 만든다.
Map<String, dynamic> gimmickLevelMap() => {
      'meta': {
        'id': 36,
        'name': '기믹 쇼케이스',
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
        {
          'x': 74,
          'y': 2,
          'width': 13,
          'material': 'WATER',
          'rate': 2,
          'total': null,
          'ash_ratio': 0.3,
        },
      ],
      'flasks': [
        {
          'x': 70,
          'y': 300,
          'w': 20,
          'h': 18,
          'goal': 25,
          'material': null,
          'state': null,
          'pure': true,
        },
      ],
      'terrain': <dynamic>[],
      'gimmicks': [
        {
          'type': 'variance_gate',
          'params': {'x': 0, 'y': 160, 'w': 160, 'h': 1, 'to': 'WATER', 'from': 'PRIMA'},
        },
        {
          'type': 'gravity_flip',
          'params': <String, dynamic>{},
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
        {
          'type': 'ash_emitter',
          'params': <String, dynamic>{},
        },
      ],
      'ink_budget': {'chalk': 100, 'heat': 0, 'frost': 0},
      'star_thresholds': null,
    };

String jsonOf(Map<String, dynamic> m) => jsonEncode(m);

/// gimmickLevelMap의 gimmicks에서 특정 type 엔트리의 params를 변형하는 헬퍼.
Map<String, dynamic> withGimmickParams(String type, Map<String, dynamic> params) {
  final m = gimmickLevelMap();
  for (final g in (m['gimmicks'] as List).cast<Map<String, dynamic>>()) {
    if (g['type'] == type) g['params'] = params;
  }
  return m;
}

void main() {
  group('기믹 정상 파싱', () {
    test('5종 기믹이 스펙으로 매핑된다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      expect(level.gimmicks.length, 5);
      final types = level.gimmicks.map((g) => g.type).toSet();
      expect(types, {
        GimmickType.varianceGate,
        GimmickType.gravityFlip,
        GimmickType.portal,
        GimmickType.tempZone,
        GimmickType.ashEmitter,
      });
    });

    test('변성 게이트 params가 보존된다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final gate =
          level.gimmicks.firstWhere((g) => g.type == GimmickType.varianceGate);
      expect(gate.params['to'], 'WATER');
      expect(gate.params['from'], 'PRIMA');
    });
  });

  group('기믹 빌더 (스펙 → sim 인스턴스)', () {
    test('게이트·포탈·온도 존·중력반전 플래그를 조립한다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final bundle = buildGimmicks(level.gimmicks,
          gridWidth: SimConstants.gridWidth);
      expect(bundle.gates.length, 1);
      expect(bundle.portals.length, 1);
      expect(bundle.zones.length, 1);
      expect(bundle.hasGravityFlip, isTrue);
    });

    test('변성 게이트 존이 row-major 셀 인덱스로 변환된다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final bundle = buildGimmicks(level.gimmicks,
          gridWidth: SimConstants.gridWidth);
      final gate = bundle.gates.single;
      expect(gate.cellIndices.length, 160, reason: '160x1 띠');
      expect(gate.cellIndices.first, 160 * SimConstants.gridWidth + 0);
      expect(gate.toMaterial, Material.water.index);
      expect(gate.fromMaterial, Material.prima.index);
    });

    test('포탈 입·출구 셀 수가 일치한다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final portal =
          buildGimmicks(level.gimmicks, gridWidth: SimConstants.gridWidth)
              .portals
              .single;
      expect(portal.entryCells.length, 25);
      expect(portal.exitCells.length, portal.entryCells.length);
    });

    test('온도 존 kind가 매핑된다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final zone =
          buildGimmicks(level.gimmicks, gridWidth: SimConstants.gridWidth)
              .zones
              .single;
      expect(zone.kind, TemperatureZoneKind.cool);
      expect(zone.probability, isNull, reason: 'null이면 룬 기본 강도');
    });

    test('기믹 없는 레벨은 빈 번들', () {
      final m = gimmickLevelMap();
      m['gimmicks'] = <dynamic>[];
      final level = loadLevelFromJson(jsonOf(m));
      final bundle = buildGimmicks(level.gimmicks,
          gridWidth: SimConstants.gridWidth);
      expect(bundle.gates, isEmpty);
      expect(bundle.hasGravityFlip, isFalse);
    });
  });

  group('직렬화 왕복 무손실 (기믹 포함)', () {
    test('serialize → load가 기믹 params를 보존한다', () {
      final level = loadLevelFromJson(jsonOf(gimmickLevelMap()));
      final round = loadLevelFromJson(serializeLevel(level));
      expect(round.gimmicks.length, level.gimmicks.length);
      for (var i = 0; i < level.gimmicks.length; i++) {
        expect(round.gimmicks[i].type, level.gimmicks[i].type);
        expect(round.gimmicks[i].params, level.gimmicks[i].params);
      }
    });
  });

  group('기믹 검증 에러 (조용한 스킵 금지)', () {
    test('변성 게이트 to 누락 → 예외', () {
      final m = withGimmickParams('variance_gate', {'x': 0, 'y': 160, 'w': 10, 'h': 1});
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('물질명이 필요')))),
      );
    });

    test('변성 게이트 결과가 정적 물질(WALL)이면 예외', () {
      final m = withGimmickParams(
          'variance_gate', {'x': 0, 'y': 160, 'w': 10, 'h': 1, 'to': 'WALL'});
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('이동 물질')))),
      );
    });

    test('변성 게이트 존이 그리드 밖이면 예외', () {
      final m = withGimmickParams('variance_gate',
          {'x': 0, 'y': 400, 'w': 10, 'h': 1, 'to': 'WATER'});
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('그리드')))),
      );
    });

    test('포탈 입·출구 셀 수 불일치 → 예외', () {
      final m = withGimmickParams('portal', {
        'entry': {'x': 4, 'y': 290, 'w': 5, 'h': 5},
        'exit': {'x': 150, 'y': 8, 'w': 4, 'h': 4},
      });
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('셀 수가 같아야')))),
      );
    });

    test('포탈 rect 객체 누락 → 예외', () {
      final m = withGimmickParams('portal', {
        'entry': {'x': 4, 'y': 290, 'w': 5, 'h': 5},
      });
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('rect 객체')))),
      );
    });

    test('온도 존 kind 오류 → 예외', () {
      final m = withGimmickParams('temp_zone',
          {'x': 0, 'y': 4, 'w': 10, 'h': 10, 'kind': 'freeze'});
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('kind')))),
      );
    });

    test('온도 존 probability 범위 밖 → 예외', () {
      final m = withGimmickParams('temp_zone',
          {'x': 0, 'y': 4, 'w': 10, 'h': 10, 'kind': 'heat', 'probability': 1.5});
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('probability')))),
      );
    });

    test('params가 객체가 아니면 예외 (마커의 params 생략은 허용)', () {
      final m = gimmickLevelMap();
      m['gimmicks'] = [
        {'type': 'gravity_flip'}, // params 생략 = 마커 정상
        {'type': 'variance_gate', 'params': 'oops'}, // 객체 아님 = 오류
      ];
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException &&
            e.problems.any((p) => p.contains('params') && p.contains('객체')))),
      );
    });

    test('알 수 없는 기믹 type → 예외', () {
      final m = gimmickLevelMap();
      m['gimmicks'] = [
        {'type': 'teleport_ray', 'params': <String, dynamic>{}},
      ];
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('알 수 없는 기믹')))),
      );
    });

    test('해금 정합 — 포탈은 챕터2부터 (챕터1에서 예외)', () {
      // 챕터1로 낮추고 챕터1에서 위법한 요소를 전부 제거, 포탈만 남긴다.
      final m = gimmickLevelMap();
      m['meta']['chapter'] = 1;
      m['meta']['optimal_ink'] = {'chalk': 80};
      m['emitters'][0]['material'] = 'PRIMA';
      m['emitters'][0]['ash_ratio'] = 0;
      m['flasks'][0]['pure'] = false;
      m['gimmicks'] = [
        {
          'type': 'portal',
          'params': {
            'entry': {'x': 4, 'y': 290, 'w': 5, 'h': 5},
            'exit': {'x': 150, 'y': 8, 'w': 5, 'h': 5},
          },
        },
      ];
      expect(
        () => loadLevelFromJson(jsonOf(m)),
        throwsA(predicate((e) =>
            e is LevelException &&
            e.problems.any((p) => p.contains('portal') && p.contains('챕터')))),
      );
    });
  });
}
