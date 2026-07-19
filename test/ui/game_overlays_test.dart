/// 인게임 오버레이·비커 테스트 (UX 3건) — 버튼 문구(평이한 한국어)·존재·크기 단언·홈 콜백 +
/// 개방형 비커 페인터 스모크.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/game/clear_overlay.dart';
import 'package:philosophers_ink/ui/game/pause_overlay.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  group('클리어 오버레이 버튼', () {
    testWidgets('다음 레벨 / 다시 하기 / 홈으로 — 문구·존재·크기', (tester) async {
      await tester.pumpWidget(_overlayHost(ClearOverlay(
        eyebrow: 'NIGREDO · LV 1',
        stars: 3,
        inkRemainingFraction: 0.4,
        inkGaugeLabel: '잉크 잔량 40 / 100',
        onNext: () {},
        onRetry: () {},
        onHome: () {},
        reducedMotion: true,
      )));
      await tester.pump(const Duration(milliseconds: 300));

      // CTA는 대문자 처리되므로 상향 매칭.
      expect(find.text('다음 레벨'.toUpperCase()), findsOneWidget);
      expect(find.text('다시 하기'.toUpperCase()), findsOneWidget);
      expect(find.text('홈으로'.toUpperCase()), findsOneWidget);
      expect(find.text('다시 정제'), findsNothing); // 옛 문구 제거 확인
      for (final t in ['다시 하기'.toUpperCase(), '홈으로'.toUpperCase()]) {
        final sz = tester.getSize(find.text(t));
        expect(sz.width, greaterThan(0));
        expect(sz.height, greaterThan(0));
      }
    });

    testWidgets('홈으로 탭이 콜백을 부른다', (tester) async {
      var home = 0;
      await tester.pumpWidget(_overlayHost(ClearOverlay(
        eyebrow: 'NIGREDO · LV 1',
        stars: 1,
        inkRemainingFraction: 0.4,
        inkGaugeLabel: '잉크 잔량 40 / 100',
        onNext: null,
        onRetry: () {},
        onHome: () => home++,
        reducedMotion: true,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('홈으로'.toUpperCase()));
      expect(home, 1);
    });
  });

  testWidgets('실패 오버레이 — 다시 하기 / 홈으로', (tester) async {
    var home = 0;
    await tester.pumpWidget(_overlayHost(
      FailOverlay(eyebrow: 'NIGREDO · LV 1', onRetry: () {}, onHome: () => home++),
    ));
    await tester.pump();
    expect(find.text('다시 하기'.toUpperCase()), findsOneWidget);
    expect(find.text('홈으로'.toUpperCase()), findsOneWidget);
    expect(tester.getSize(find.text('홈으로'.toUpperCase())).width,
        greaterThan(0));
    await tester.tap(find.text('홈으로'.toUpperCase()));
    expect(home, 1);
  });

  testWidgets('일시정지 오버레이 — 다시 하기 / 홈으로 (평이한 문구)', (tester) async {
    await tester.pumpWidget(_overlayHost(PauseOverlay(
      eyebrow: 'NIGREDO · LV 1',
      onResume: () {},
      onRetry: () {},
      onExit: () {},
      muted: false,
      onToggleMute: () {},
    )));
    await tester.pump();
    expect(find.text('다시 하기'.toUpperCase()), findsOneWidget);
    expect(find.text('홈으로'.toUpperCase()), findsOneWidget);
    expect(find.text('재시작'.toUpperCase()), findsNothing);
    expect(find.text('나가기'.toUpperCase()), findsNothing);
  });

  testWidgets('개방형 비커 페인터 스모크 — 조건 플라스크(물질/상태/순수) 예외 없이 렌더', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(ProgressStore(prefs), const {});
    final entry = LevelEntry(
      id: 21,
      chapter: 2,
      name: 'L21',
      assetPath: 'assets/levels/level_021.json',
      level: const Level(
        meta: LevelMeta(id: 21, name: 'L21', chapter: 2, difficulty: 4),
        background: 0xFF101010,
        emitters: [],
        flasks: [
          FlaskSpec(
              x: 10,
              y: 20,
              w: 20,
              h: 30,
              goal: 8,
              material: Material.water,
              state: FlaskState.solid,
              pure: true),
        ],
        inkBudget: {InkType.chalk: 20},
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: PlayScreen(
        entry: entry,
        progress: GameProgress(),
        settings: settings,
        audio: const SilentAudioService(),
        onboarding: OnboardingState(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull, reason: '비커 페인터가 예외 없이 그린다');
    expect(tester.getSize(find.byType(PlayScreen)).width, greaterThan(0));
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink()); // 온보딩 타이머 정리
  });
}
