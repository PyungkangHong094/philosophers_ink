import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/debug_hud.dart';
import 'package:philosophers_ink/gameplay/ink_budget.dart';
import 'package:philosophers_ink/gameplay/ink_controller.dart';
import 'package:philosophers_ink/sim/materials.dart';

Widget _wrap(InkController c) => MaterialApp(
      home: Scaffold(body: Center(child: InkHud(controller: c))),
    );

void main() {
  testWidgets('숨김 잉크(예산 0)는 병을 그리지 않는다', (tester) async {
    final c = InkController(InkBudget(chalk: 100)); // heat/frost 숨김
    await tester.pumpWidget(_wrap(c));

    expect(find.text('석필'), findsOneWidget);
    expect(find.text('화염'), findsNothing);
    expect(find.text('서리'), findsNothing);
    expect(find.text('100'), findsOneWidget, reason: '잔량 표시');
  });

  testWidgets('노출 잉크가 없으면 아무것도 그리지 않는다', (tester) async {
    final c = InkController(InkBudget());
    await tester.pumpWidget(_wrap(c));
    expect(find.byType(InkHud), findsOneWidget);
    expect(find.text('석필'), findsNothing);
  });

  testWidgets('병 탭 → 선택 변경', (tester) async {
    final c = InkController(InkBudget(chalk: 100, frost: 50));
    await tester.pumpWidget(_wrap(c));
    expect(c.selected, InkType.chalk);

    await tester.tap(find.text('서리'));
    await tester.pump();
    expect(c.selected, InkType.frost);
  });

  testWidgets('차감 후 잔량 텍스트가 갱신된다', (tester) async {
    final c = InkController(InkBudget(chalk: 100));
    await tester.pumpWidget(_wrap(c));
    expect(find.text('100'), findsOneWidget);

    c.chargePlaced(40); // ChangeNotifier → HUD 리빌드
    await tester.pump();
    expect(find.text('60'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });
}
