import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/editor/editor_document.dart';
import 'package:philosophers_ink/level/level_exception.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';

void main() {
  group('EditorDocument', () {
    test('빈 문서는 방출구·플라스크가 없어 build 시 명시적 에러', () {
      final doc = EditorDocument.blank();
      expect(() => doc.build(), throwsA(isA<LevelException>()));
    });

    test('처음부터 저작 → 유효 레벨 build', () {
      final doc = EditorDocument.blank(id: 1)
        ..addEmitter(const EmitterSpec(x: 80, y: 2, material: Material.prima, rate: 1))
        ..addFlask(const FlaskSpec(x: 100, y: 280, w: 20, h: 20, goal: 30))
        ..setInkBudget(InkType.chalk, 100);
      final level = doc.build();
      expect(level.emitters.single.material, Material.prima);
      expect(level.flasks.single.goal, 30);
    });

    test('fromLevel → exportJson → 재로드 왕복 무손실', () {
      final original =
          loadLevelFromJson(File('assets/levels/level_021.json').readAsStringSync());
      final doc = EditorDocument.fromLevel(original);
      final reloaded = doc.reloadExported();
      expect(reloaded.meta.id, original.meta.id);
      // 출고 레벨은 콘텐츠라 요소 개수가 변한다 — 개수 하드커플 금지, 보존만 단언.
      expect(reloaded.flasks.length, original.flasks.length);
      expect(reloaded.flasks.any((f) => f.state == FlaskState.solid), isTrue);
      expect(reloaded.emitters.length, original.emitters.length);
      expect(reloaded.emitters.first.material, original.emitters.first.material);
      expect(reloaded.inkBudget, original.inkBudget);
      expect(reloaded.terrain.length, original.terrain.length);
      expect(reloaded.terrain.first.material, original.terrain.first.material);
    });

    test('편집 후 무효 상태는 build에서 잡힌다 (그리드 밖 플라스크)', () {
      final doc = EditorDocument.blank(id: 2)
        ..addEmitter(const EmitterSpec(x: 80, y: 2, material: Material.prima, rate: 1))
        ..addFlask(const FlaskSpec(x: 9999, y: 0, w: 5, h: 5, goal: 10))
        ..setInkBudget(InkType.chalk, 100);
      expect(
        () => doc.build(),
        throwsA(predicate((e) =>
            e is LevelException && e.problems.any((p) => p.contains('그리드')))),
      );
    });

    test('fromLevel은 원본 리스트를 건드리지 않는다', () {
      final original =
          loadLevelFromJson(File('assets/levels/level_001.json').readAsStringSync());
      final doc = EditorDocument.fromLevel(original)
        ..addFlask(const FlaskSpec(x: 0, y: 0, w: 2, h: 2, goal: 5));
      expect(original.flasks.length, 1, reason: '원본 불변');
      expect(doc.flasks.length, 2);
    });
  });
}
