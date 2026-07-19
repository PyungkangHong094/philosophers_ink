/// HUD 테스트 — 초시계 포맷(순수) + 표시·정지·리셋 + 잉크 팔레트 우측 상단 이동.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/game/hud_format.dart';
import 'package:philosophers_ink/ui/game/ink_palette_bar.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MM:SS 텍스트 파인더 (초시계).
final _stopwatch = find.byWidgetPredicate((w) =>
    w is Text && w.data != null && RegExp(r'^\d\d:\d\d$').hasMatch(w.data!));

String _stopwatchText(WidgetTester t) => (t.widget<Text>(_stopwatch)).data!;

void main() {
  group('formatElapsed (60Hz 틱 기반)', () {
    test('틱 → MM:SS', () {
      expect(formatElapsed(0), '00:00');
      expect(formatElapsed(60), '00:01'); // 60틱 = 1초
      expect(formatElapsed(600), '00:10');
      expect(formatElapsed(3600), '01:00'); // 3600틱 = 60초
      expect(formatElapsed(6000), '01:40');
      expect(formatElapsed(36000), '10:00');
    });

    test('초 미만은 00:00 (내림)', () {
      expect(formatElapsed(59), '00:00');
      expect(formatElapsed(119), '00:01');
    });
  });

  group('인게임 초시계·팔레트', () {
    late SettingsController settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsController(ProgressStore(prefs), const {});
    });

    LevelEntry makeEntry() => LevelEntry(
          id: 1,
          chapter: 1,
          name: 'L1',
          assetPath: 'assets/levels/level_001.json',
          level: const Level(
            meta: LevelMeta(id: 1, name: 'L1', chapter: 1, difficulty: 1),
            background: 0xFF101010,
            emitters: [],
            flasks: [FlaskSpec(x: 10, y: 10, w: 8, h: 8, goal: 4)],
            inkBudget: {InkType.chalk: 20},
          ),
        );

    Future<void> pumpPlay(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlayScreen(
          entry: makeEntry(),
          progress: GameProgress(),
          settings: settings,
          audio: const SilentAudioService(),
          onboarding: OnboardingState(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('초시계가 00:00부터 표시되고 크기를 가진다', (tester) async {
      await pumpPlay(tester);
      expect(_stopwatch, findsOneWidget);
      expect(_stopwatchText(tester), '00:00');
      expect(tester.getSize(_stopwatch).width, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('시간이 흐르면 증가하고, 재시작하면 00:00으로 리셋', (tester) async {
      await pumpPlay(tester);
      // 시뮬 틱 누적 (프레임당 최대 0.25s=15틱). 몇 초 흘린다.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_stopwatchText(tester), isNot('00:00'), reason: '시간이 흘러야 한다');

      // 재시작 버튼(새로고침 아이콘) → 초시계 리셋.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_stopwatchText(tester), '00:00', reason: '재시작이 초시계를 리셋');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('일시정지 중에는 초시계가 멈춘다', (tester) async {
      await pumpPlay(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final before = _stopwatchText(tester);
      expect(before, isNot('00:00'));

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(milliseconds: 16));
      // 정지 상태로 시간 경과 시뮬.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_stopwatchText(tester), before, reason: '일시정지 중 초시계 정지');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('잉크 팔레트가 우측 상단으로 이동 (존재·크기·위치)', (tester) async {
      await pumpPlay(tester);
      expect(find.byType(InkPaletteBar), findsOneWidget);
      final screen = tester.getSize(find.byType(PlayScreen));
      final palette = tester.getRect(find.byType(InkPaletteBar));
      expect(palette.width, greaterThan(0));
      expect(palette.height, greaterThan(0));
      // 우측(중심 x가 화면 우측 절반) + 상단(중심 y가 화면 상단 절반).
      expect(palette.center.dx, greaterThan(screen.width / 2),
          reason: '팔레트가 우측에 있어야 한다');
      expect(palette.center.dy, lessThan(screen.height / 2),
          reason: '팔레트가 상단에 있어야 한다');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
