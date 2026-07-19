/// 레벨 → JSON 직렬화 (에디터 익스포트의 핵심). 순수 Dart.
///
/// [loader]와 무손실 왕복을 보장한다: loadLevelFromJson(serializeLevel(level))가
/// 같은 레벨을 복원한다. 파일 쓰기(path_provider/dart:io)는 이 계층 밖(에디터 UI)에서
/// 이 문자열을 받아 처리한다 — 직렬화 자체는 I/O에 의존하지 않아 테스트 가능하다.
library;

import 'dart:convert';

import 'level_model.dart';

String _inkKey(InkType t) => switch (t) {
      InkType.chalk => 'chalk',
      InkType.heat => 'heat',
      InkType.frost => 'frost',
    };

/// 0xAARRGGBB → "#RRGGBB"(불투명) 또는 "#AARRGGBB". 로더가 양쪽 다 읽는다.
String _colorToHex(int argb) {
  final a = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  if (a == 0xFF) return '#$rgb';
  final aa = a.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#$aa$rgb';
}

Map<String, int> _inkMapToJson(Map<InkType, int> m) => {
      for (final e in m.entries) _inkKey(e.key): e.value,
    };

/// 레벨을 JSON 직렬화 가능한 맵으로.
Map<String, dynamic> levelToMap(Level level) {
  final meta = level.meta;
  return {
    'meta': {
      'id': meta.id,
      'name': meta.name,
      'chapter': meta.chapter,
      'difficulty': meta.difficulty,
      'teaches': meta.teaches,
      'tags': meta.tags,
      'optimal_ink':
          meta.optimalInk == null ? null : _inkMapToJson(meta.optimalInk!),
      'solutions_verified': meta.solutionsVerified,
      'hint_stroke': meta.hintStroke,
    },
    'background': _colorToHex(level.background),
    'emitters': [
      for (final e in level.emitters)
        {
          'x': e.x,
          'y': e.y,
          'width': e.width,
          'material': materialName(e.material),
          'rate': e.rate,
          'total': e.total,
          'ash_ratio': e.ashRatio,
        },
    ],
    'flasks': [
      for (final f in level.flasks)
        {
          'x': f.x,
          'y': f.y,
          'w': f.w,
          'h': f.h,
          'goal': f.goal,
          'material': f.material == null ? null : materialName(f.material!),
          'state': f.state?.key,
          'pure': f.pure,
          'mouth': f.mouth.key,
        },
    ],
    'terrain': [
      for (final t in level.terrain)
        {
          'x': t.x,
          'y': t.y,
          'w': t.w,
          'h': t.h,
          'material': materialName(t.material),
        },
    ],
    'gimmicks': [
      for (final g in level.gimmicks) {'type': g.type, 'params': g.params},
    ],
    'ink_budget': _inkMapToJson(level.inkBudget),
    'star_thresholds': level.starThresholds == null
        ? null
        : {
            'two_star': level.starThresholds!.twoStar,
            'three_star': level.starThresholds!.threeStar,
          },
  };
}

/// 레벨을 들여쓰기된 JSON 문자열로 (에디터 익스포트).
String serializeLevel(Level level) =>
    const JsonEncoder.withIndent('  ').convert(levelToMap(level));
