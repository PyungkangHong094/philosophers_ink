import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:philosophers_ink/main.dart';

void main() {
  testWidgets('M2 게임 화면이 빌드되고 리셋 버튼이 뜬다', (tester) async {
    await tester.pumpWidget(const PhilosophersInkApp());
    // 한 프레임만 진행 (Ticker가 매 프레임 재예약하므로 pumpAndSettle 금지).
    await tester.pump(const Duration(milliseconds: 16));

    // 세션 로드 여부와 무관하게 항상 존재하는 요소.
    expect(find.text('RESET'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
