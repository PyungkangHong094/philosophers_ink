/// 온보딩 위젯 테스트 (GDD 7.2) — 노출/소멸 + 임계·별점 설명 표시. **크기 단언 포함**
/// (0×0 회귀 교훈 — 존재 검사만으로는 안 된다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/ui/game/clear_overlay.dart';
import 'package:philosophers_ink/ui/game/pause_overlay.dart';
import 'package:philosophers_ink/ui/onboarding/onboarding_widgets.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// Positioned.fill 오버레이는 Stack 안에서만 배치된다 — 크기 있는 Stack으로 감싼다.
Widget _overlayHost(Widget overlay) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: Stack(children: [overlay]),
        ),
      ),
    );

void main() {
  testWidgets('목표 배너가 노출되고 실제 크기를 가진다', (tester) async {
    await tester.pumpWidget(
      _host(const GoalBanner(text: '프리마를 플라스크에 35만큼 담아라', visible: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('프리마를 플라스크에 35만큼 담아라'), findsOneWidget);
    final size = tester.getSize(find.text('프리마를 플라스크에 35만큼 담아라'));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    // 배너 컨테이너도 실제 크기.
    expect(tester.getSize(find.byType(GoalBanner)).height, greaterThan(0));
  });

  testWidgets('목표 배너가 visible=false 시 페이드아웃(불투명도 0)', (tester) async {
    await tester.pumpWidget(
      _host(const GoalBanner(text: '목표 문구', visible: false)),
    );
    await tester.pumpAndSettle();
    final op = tester.widget<AnimatedOpacity>(
      find.descendant(
          of: find.byType(GoalBanner), matching: find.byType(AnimatedOpacity)),
    );
    expect(op.opacity, 0.0);
  });

  testWidgets('첫 조작 가이드가 텍스트+아이콘을 크기 있게 그린다', (tester) async {
    await tester.pumpWidget(
      _host(const FirstOpGuide(
        text: '화면에 선을 그어 길을 만들어라',
        icon: Icons.gesture,
        reducedMotion: true, // 반복 애니 없이 정적
      )),
    );
    await tester.pump();
    expect(find.text('화면에 선을 그어 길을 만들어라'), findsOneWidget);
    expect(find.byIcon(Icons.gesture), findsOneWidget);
    expect(tester.getSize(find.text('화면에 선을 그어 길을 만들어라')).width,
        greaterThan(0));
    expect(tester.getSize(find.byIcon(Icons.gesture)).width, greaterThan(0));
  });

  testWidgets('일시정지 오버레이가 별점 임계를 크기 있게 표시', (tester) async {
    await tester.pumpWidget(_overlayHost(
      PauseOverlay(
        eyebrow: 'NIGREDO · LV 1',
        onResume: () {},
        onRetry: () {},
        onExit: () {},
        muted: false,
        onToggleMute: () {},
        thresholdLine: '★★ ≤ 100 · ★★★ ≤ 60',
      ),
    ));
    await tester.pump();
    expect(find.text('★★ ≤ 100 · ★★★ ≤ 60'), findsOneWidget);
    expect(tester.getSize(find.text('★★ ≤ 100 · ★★★ ≤ 60')).width,
        greaterThan(0));
  });

  testWidgets('클리어 오버레이가 첫 클리어 별점 설명+사용량을 크기 있게 표시', (tester) async {
    await tester.pumpWidget(_overlayHost(
      ClearOverlay(
        eyebrow: 'NIGREDO · LV 1',
        stars: 3,
        inkRemainingFraction: 0.4,
        inkGaugeLabel: '잉크 잔량 40 / 100',
        onNext: () {},
        onRetry: () {},
        reducedMotion: true,
        starHelp: '잉크를 아낄수록 별이 오른다',
        usageLine: '사용 80 · ★★★ ≤ 60',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('잉크를 아낄수록 별이 오른다'), findsOneWidget);
    expect(find.text('사용 80 · ★★★ ≤ 60'), findsOneWidget);
    expect(tester.getSize(find.text('잉크를 아낄수록 별이 오른다')).width,
        greaterThan(0));
    expect(tester.getSize(find.text('사용 80 · ★★★ ≤ 60')).height,
        greaterThan(0));
  });

  testWidgets('클리어 오버레이가 재플레이(starHelp=null) 시 설명 숨김', (tester) async {
    await tester.pumpWidget(_overlayHost(
      ClearOverlay(
        eyebrow: 'NIGREDO · LV 1',
        stars: 2,
        inkRemainingFraction: 0.4,
        inkGaugeLabel: '잉크 잔량 40 / 100',
        onNext: () {},
        onRetry: () {},
        reducedMotion: true,
        starHelp: null,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('잉크를 아낄수록 별이 오른다'), findsNothing);
  });
}
