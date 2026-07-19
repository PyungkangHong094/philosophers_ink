/// 힌트 버튼 노출 조건 (GDD 12) — hint_stroke 유무·작업(OPERATIO) 레벨 여부·탭 후 상태.
/// 존재 검사만 하지 않고 실제 크기를 단언한다.
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
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsController settings;
  late Monetization monetization;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsController(ProgressStore(prefs), const {});
    monetization = Monetization.create(ProgressStore(prefs), forceStub: true);
  });

  // id·hintStroke를 바꿔가며 레벨 엔트리를 만든다.
  LevelEntry entry({required int id, List<HintStroke>? hint}) => LevelEntry(
        id: id,
        chapter: 1,
        name: 'L$id',
        assetPath: 'assets/levels/level_$id.json',
        level: Level(
          meta: LevelMeta(
              id: id,
              name: 'L$id',
              chapter: 1,
              difficulty: 1,
              hintStroke: hint),
          background: 0xFF101010,
          emitters: const [],
          flasks: const [FlaskSpec(x: 10, y: 10, w: 8, h: 8, goal: 4)],
          inkBudget: const {InkType.chalk: 20},
        ),
      );

  Future<void> pump(WidgetTester tester, LevelEntry e) async {
    await tester.pumpWidget(MaterialApp(
      home: PlayScreen(
        entry: e,
        progress: GameProgress(),
        settings: settings,
        audio: const SilentAudioService(),
        onboarding: OnboardingState(),
        monetization: monetization,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
  }

  final hintFinder = find.byIcon(Icons.lightbulb_outline);

  testWidgets('hint_stroke가 있고 작업 레벨이 아니면 힌트 버튼이 실제 크기로 뜬다',
      (tester) async {
    await pump(tester, entry(id: 3, hint: [
      HintStroke(ink: InkType.chalk, x0: 10, y0: 10, x1: 40, y1: 60),
    ]));
    expect(hintFinder, findsOneWidget);
    final size = tester.getSize(hintFinder);
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink()); // 타이머 정리.
  });

  testWidgets('작업(OPERATIO·11배수) 레벨은 hint_stroke가 있어도 버튼을 숨긴다',
      (tester) async {
    await pump(tester, entry(id: 11, hint: [
      HintStroke(ink: InkType.chalk, x0: 10, y0: 10, x1: 40, y1: 60),
    ]));
    expect(hintFinder, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hint_stroke가 null이면 버튼을 숨긴다', (tester) async {
    await pump(tester, entry(id: 3, hint: null));
    expect(hintFinder, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('힌트 탭 → 보상 성공(스텁) 후 버튼이 사라지고 고스트가 노출된다',
      (tester) async {
    await pump(tester, entry(id: 3, hint: [
      HintStroke(ink: InkType.chalk, x0: 10, y0: 10, x1: 40, y1: 60),
    ]));
    expect(hintFinder, findsOneWidget);
    // 탭 전 CustomPaint 수(캔버스·플라스크 HUD 등).
    final before = tester.widgetList(find.byType(CustomPaint)).length;

    await tester.tap(hintFinder);
    await tester.pump(); // requestHint(async 스텁) 완료.
    await tester.pump(const Duration(milliseconds: 16));

    expect(hintFinder, findsNothing, reason: '힌트 표시 후 버튼 숨김');
    expect(tester.takeException(), isNull);
    // 고스트 라인 CustomPaint가 추가됐다.
    final after = tester.widgetList(find.byType(CustomPaint)).length;
    expect(after, greaterThan(before), reason: '고스트 오버레이 CustomPaint 추가');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
