/// HUD 테스트 — 시계 포맷(순수) + 인게임 카운트다운 표시·감소·정지·리셋·임박 경고색 +
/// 잉크 팔레트 우측 상단 이동.
///
/// 상단 HUD 시간은 **카운트다운**(제한 시간 → 0)이다 (GDD 2장 제한 시간제, 2026-07-19 개정).
/// 시작값=제한 시간, 시뮬 경과 시 감소, 재시작 시 제한 시간으로 복귀, ≤10초는 warn 색.
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
import 'package:philosophers_ink/ui/game/hud_format.dart';
import 'package:philosophers_ink/ui/game/ink_palette_bar.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:philosophers_ink/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MM:SS 텍스트 파인더 (카운트다운). 인게임 활성 중 유일한 MM:SS 텍스트.
final _countdown = find.byWidgetPredicate((w) =>
    w is Text && w.data != null && RegExp(r'^\d\d:\d\d$').hasMatch(w.data!));

String _countdownText(WidgetTester t) => (t.widget<Text>(_countdown)).data!;
Color? _countdownColor(WidgetTester t) => (t.widget<Text>(_countdown)).style?.color;

/// "MM:SS" → 총 초 (감소 단언용).
int _seconds(String mmss) {
  final p = mmss.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

void main() {
  group('formatClock (카운트다운 포맷)', () {
    test('초 → MM:SS', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(8), '00:08');
      expect(formatClock(120), '02:00');
      expect(formatClock(3599), '59:59');
    });

    test('음수는 00:00으로 클램프', () {
      expect(formatClock(-1), '00:00');
      expect(formatClock(-120), '00:00');
    });
  });

  group('formatElapsed (60Hz 틱 기반 — 클리어 소요 시간)', () {
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

  group('인게임 카운트다운·팔레트', () {
    late SettingsController settings;
    late Monetization monetization;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsController(ProgressStore(prefs), const {});
      monetization =
          Monetization.create(ProgressStore(prefs), forceStub: true);
    });

    /// 제한 시간 120초(=02:00) 레벨. 임박(≤10초) 밖이라 카운트다운은 평상 색.
    LevelEntry makeEntry({int timeLimitSeconds = 120}) => LevelEntry(
          id: 1,
          chapter: 1,
          name: 'L1',
          assetPath: 'assets/levels/level_001.json',
          level: Level(
            meta: const LevelMeta(id: 1, name: 'L1', chapter: 1, difficulty: 1),
            background: 0xFF101010,
            emitters: const [],
            flasks: const [FlaskSpec(x: 10, y: 10, w: 8, h: 8, goal: 4)],
            inkBudget: const {InkType.chalk: 20},
            timeLimitSeconds: timeLimitSeconds,
          ),
        );

    Future<void> pumpPlay(WidgetTester tester, {LevelEntry? entry}) async {
      await tester.pumpWidget(MaterialApp(
        home: PlayScreen(
          entry: entry ?? makeEntry(),
          progress: GameProgress(),
          settings: settings,
          audio: const SilentAudioService(),
          onboarding: OnboardingState(),
          monetization: monetization,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('카운트다운이 제한 시간부터 표시되고 크기·평상색을 가진다', (tester) async {
      await pumpPlay(tester);
      expect(_countdown, findsOneWidget);
      expect(_countdownText(tester), '02:00', reason: '제한 시간 120초부터 시작');
      expect(tester.getSize(_countdown).width, greaterThan(0));
      // 120초는 임박(≤10초) 밖 → 골드 아닌 평상 parchment 색.
      expect(_countdownColor(tester), InkColor.parchment);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('시간이 흐르면 감소하고, 재시작하면 제한 시간으로 복귀', (tester) async {
      await pumpPlay(tester);
      // 시뮬 틱 누적 (프레임당 최대 0.25s). 몇 초 흘린다.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_seconds(_countdownText(tester)), lessThan(120),
          reason: '카운트다운은 감소해야 한다');

      // 재시작 버튼(새로고침 아이콘) → 카운트다운 리셋(제한 시간 복귀).
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_countdownText(tester), '02:00', reason: '재시작이 카운트다운을 제한 시간으로 리셋');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('일시정지 중에는 카운트다운이 멈춘다', (tester) async {
      await pumpPlay(tester);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final before = _countdownText(tester);
      expect(_seconds(before), lessThan(120), reason: '먼저 시간이 흘러야 정지 검증이 의미 있다');

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(milliseconds: 16));
      // 정지 상태로 시간 경과 시뮬.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_countdownText(tester), before, reason: '일시정지 중 카운트다운 정지');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('임박(≤10초)이면 카운트다운이 경고색(warn)으로 표시된다', (tester) async {
      // 제한 시간 8초 → 시작부터 임박 → warn 색(골드 아님, 희소성 보존).
      await pumpPlay(tester, entry: makeEntry(timeLimitSeconds: 8));
      expect(_countdownText(tester), '00:08');
      expect(_countdownColor(tester), InkColor.warn,
          reason: '≤10초는 warn 주홍색');
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
