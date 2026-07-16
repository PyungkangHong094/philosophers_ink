import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:philosophers_ink/main.dart';

void main() {
  testWidgets('M0 스파이크 씬이 빌드되고 디버그 오버레이·리셋이 뜬다', (tester) async {
    await tester.pumpWidget(const PhilosophersInkApp());
    // 한 프레임만 진행 (Ticker가 매 프레임 재예약하므로 pumpAndSettle 금지).
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('RESET'), findsOneWidget);
    expect(find.textContaining('grid 160x320'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
