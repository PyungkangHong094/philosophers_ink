import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/serializer.dart';

/// 두 레벨의 주요 필드가 같은지 검사 (Level에 == 없음).
void _expectSameLevel(Level a, Level b) {
  expect(b.meta.id, a.meta.id);
  expect(b.meta.name, a.meta.name);
  expect(b.meta.chapter, a.meta.chapter);
  expect(b.meta.difficulty, a.meta.difficulty);
  expect(b.meta.teaches, a.meta.teaches);
  expect(b.meta.tags, a.meta.tags);
  expect(b.meta.optimalInk, a.meta.optimalInk);
  expect(b.meta.solutionsVerified, a.meta.solutionsVerified);
  expect(b.background, a.background);
  expect(b.inkBudget, a.inkBudget);

  expect(b.emitters.length, a.emitters.length);
  for (var i = 0; i < a.emitters.length; i++) {
    expect(b.emitters[i].x, a.emitters[i].x);
    expect(b.emitters[i].y, a.emitters[i].y);
    expect(b.emitters[i].width, a.emitters[i].width);
    expect(b.emitters[i].material, a.emitters[i].material);
    expect(b.emitters[i].rate, a.emitters[i].rate);
    expect(b.emitters[i].total, a.emitters[i].total);
    expect(b.emitters[i].ashRatio, a.emitters[i].ashRatio);
  }

  expect(b.flasks.length, a.flasks.length);
  for (var i = 0; i < a.flasks.length; i++) {
    expect(b.flasks[i].x, a.flasks[i].x);
    expect(b.flasks[i].y, a.flasks[i].y);
    expect(b.flasks[i].w, a.flasks[i].w);
    expect(b.flasks[i].h, a.flasks[i].h);
    expect(b.flasks[i].goal, a.flasks[i].goal);
    expect(b.flasks[i].material, a.flasks[i].material);
    expect(b.flasks[i].state, a.flasks[i].state);
    expect(b.flasks[i].pure, a.flasks[i].pure);
  }

  expect(b.terrain.length, a.terrain.length);
  for (var i = 0; i < a.terrain.length; i++) {
    expect(b.terrain[i].material, a.terrain[i].material);
    expect(b.terrain[i].x, a.terrain[i].x);
  }
}

void main() {
  group('에디터 export → loader 라운드트립 무손실 (핵심 요구)', () {
    test('level_001 왕복', () {
      final level =
          loadLevelFromJson(File('assets/levels/level_001.json').readAsStringSync());
      final round = loadLevelFromJson(serializeLevel(level));
      _expectSameLevel(level, round);
    });

    test('level_021 왕복 (상태 플라스크 + 지형 + optimal_ink)', () {
      final level =
          loadLevelFromJson(File('assets/levels/level_021.json').readAsStringSync());
      final round = loadLevelFromJson(serializeLevel(level));
      _expectSameLevel(level, round);
      // 출고 레벨은 콘텐츠라 개수가 변한다 — 존재·보존만 단언 (개수 하드커플 금지).
      expect(round.flasks.any((f) => f.state == FlaskState.solid), isTrue,
          reason: '021은 상태(고체) 플라스크 교육 레벨');
      expect(round.terrain, isNotEmpty);
      expect(round.terrain.first.material, Material.wall);
    });

    test('직렬화 결과는 다시 검증을 통과한다', () {
      final level =
          loadLevelFromJson(File('assets/levels/level_021.json').readAsStringSync());
      // serialize → load가 예외 없이 통과하면 검증 라운드트립 성립.
      expect(() => loadLevelFromJson(serializeLevel(level)), returnsNormally);
    });
  });
}
