import 'package:flutter/material.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/editor/editor_document.dart';
import 'package:philosophers_ink/level/editor/editor_screen.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/level/loader.dart';

EditorDocument _validDoc() => EditorDocument.blank(id: 1)
  ..addEmitter(const EmitterSpec(
      x: 74, y: 2, width: 13, material: Material.prima, rate: 1))
  ..addFlask(const FlaskSpec(x: 100, y: 280, w: 16, h: 16, goal: 50))
  ..setInkBudget(InkType.chalk, 300);

void main() {
  testWidgets('에디터: 익스포트 sink가 로더 왕복 가능한 JSON을 받는다', (tester) async {
    String? exported;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        initial: _validDoc(),
        onExport: (json, name) async => exported = json,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('익스포트'));
    await tester.pump();
    await tester.pump();

    expect(exported, isNotNull);
    final level = loadLevelFromJson(exported!);
    expect(level.flasks.single.goal, 50);
    expect(level.emitters.single.material, Material.prima);
  });

  testWidgets('에디터: 무효 문서 익스포트는 검증 실패 스낵바 (조용한 저장 금지)', (tester) async {
    String? exported;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        // 방출구·플라스크 없는 빈 문서 → 검증 실패.
        initial: EditorDocument.blank(id: 2),
        onExport: (json, name) async => exported = json,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('익스포트'));
    await tester.pump();

    expect(exported, isNull, reason: '검증 실패 시 sink 호출 안 함');
    expect(find.textContaining('검증 실패'), findsOneWidget);
  });

  testWidgets('에디터: 도구 전환이 반영된다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(initial: _validDoc())));
    await tester.pump();
    // 방출 1 / 플라스크 1 카운트가 툴바에 뜬다.
    expect(find.textContaining('방출 1'), findsOneWidget);
    expect(find.textContaining('플라스크 1'), findsOneWidget);
  });
}
