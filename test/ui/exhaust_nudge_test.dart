/// 잉크 소진 넛지 테스트 (P2) — 위젯(문구·크기·탭·reduced) + 노출 조건(잉크 소진 8초 후).
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/monetize/monetization.dart';
import 'package:philosophers_ink/ui/game/exhaust_nudge.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('InkExhaustNudge 위젯', () {
    testWidgets('문구·아이콘을 크기 있게 그린다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: InkExhaustNudge(onRetry: () {}, reducedMotion: true),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text(InkExhaustNudge.message), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      final sz = tester.getSize(find.text(InkExhaustNudge.message));
      expect(sz.width, greaterThan(0));
      expect(sz.height, greaterThan(0));
    });

    testWidgets('탭이 재시작 콜백을 부른다', (tester) async {
      var retry = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: InkExhaustNudge(onRetry: () => retry++, reducedMotion: false),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(InkExhaustNudge.message));
      expect(retry, 1);
    });
  });

  group('노출 조건 (잉크 소진 + 8초)', () {
    late SettingsController settings;
    late Monetization monetization;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsController(ProgressStore(prefs), const {});
      monetization =
          Monetization.create(ProgressStore(prefs), forceStub: true);
    });

    // 석필 예산 1 — 한 획이면 소진된다.
    LevelEntry makeEntry() => LevelEntry(
          id: 3,
          chapter: 1,
          name: 'L3',
          assetPath: 'assets/levels/level_003.json',
          level: const Level(
            meta: LevelMeta(id: 3, name: 'L3', chapter: 1, difficulty: 2),
            background: 0xFF101010,
            emitters: [],
            flasks: [FlaskSpec(x: 10, y: 10, w: 8, h: 8, goal: 4)],
            inkBudget: {InkType.chalk: 1},
          ),
        );

    testWidgets('소진 즉시엔 없고, 8초 경과 후 넛지가 뜬다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlayScreen(
          entry: makeEntry(),
          progress: GameProgress(),
          settings: settings,
          audio: const SilentAudioService(),
          onboarding: OnboardingState(),
          monetization: monetization,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // 캔버스를 드래그해 석필을 소진(예산 1).
      await tester.drag(find.byType(PlayScreen), const Offset(60, 60));
      await tester.pump(const Duration(milliseconds: 16));

      // 8초 전에는 넛지 없음.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(InkExhaustNudge), findsNothing);

      // 8초 경과 후 노출.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(InkExhaustNudge), findsOneWidget);
      expect(tester.getSize(find.byType(InkExhaustNudge)).width, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink()); // 타이머 정리
    });
  });
}
