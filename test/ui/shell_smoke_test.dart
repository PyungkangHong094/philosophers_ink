/// 셸 화면 스모크 테스트 — 핵심 화면이 빌드되고 주요 요소가 뜨는지 확인.
///
/// 타이틀은 반복 애니메이션이 있어 pumpAndSettle 금지 — 고정 시간 pump만 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/chapters.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/ui/app.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/screens/chapter_select_screen.dart';
import 'package:philosophers_ink/ui/screens/level_select_screen.dart';
import 'package:philosophers_ink/ui/screens/settings_screen.dart';
import 'package:philosophers_ink/ui/screens/title_screen.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelEntry _entry(int id, int chapter) => LevelEntry(
      id: id,
      chapter: chapter,
      name: 'L$id',
      assetPath: 'assets/levels/level_$id.json',
      level: Level(
        meta: LevelMeta(id: id, name: 'L$id', chapter: chapter, difficulty: 1),
        background: 0xFF101010,
        emitters: const [],
        flasks: const [
          FlaskSpec(x: 10, y: 10, w: 8, h: 8, goal: 4),
        ],
        inkBudget: const {InkType.chalk: 20},
      ),
    );

void main() {
  late SettingsController settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsController(ProgressStore(prefs), const {});
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    LevelCatalog? catalog,
    GameProgress? progress,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InkServices(
          settings: settings,
          progress: progress ?? GameProgress(),
          catalog: catalog ?? LevelCatalog(const []),
          audio: const SilentAudioService(),
          child: screen,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('타이틀 화면이 로고와 시작 문구를 그린다', (tester) async {
    await pumpScreen(tester, const TitleScreen());
    expect(find.text('INK'), findsOneWidget);
    expect(find.text('현자의 잉크'), findsOneWidget);
    expect(find.text('화면을 터치하여 시작'), findsOneWidget);
  });

  testWidgets('챕터 선택이 4챕터 라틴명을 그리고 잠금 챕터를 표시한다', (tester) async {
    final catalog = LevelCatalog([_entry(1, 1)]);
    await pumpScreen(tester, const ChapterSelectScreen(), catalog: catalog);
    expect(find.text('NIGREDO'), findsOneWidget);
    expect(find.text('RUBEDO'), findsOneWidget);
    // 챕터 2는 콘텐츠 없고 잠김 → 해금 안내 노출.
    expect(find.textContaining('완료 시 해금'), findsWidgets);
  });

  testWidgets('레벨 선택이 정원만큼 셀을 그리고 존재 레벨 번호를 표시한다', (tester) async {
    final catalog = LevelCatalog([_entry(1, 1), _entry(2, 1)]);
    await pumpScreen(
      tester,
      LevelSelectScreen(chapter: kChapters[0]),
      catalog: catalog,
    );
    expect(find.text('NIGREDO'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // 현재 셀
    expect(find.text('2'), findsOneWidget); // 잠금 셀
  });

  testWidgets('설정 화면 토글이 값을 반전시킨다', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    expect(settings.reducedMotion, isFalse);
    await tester.tap(find.text('모션 줄이기'));
    await tester.pump();
    expect(settings.reducedMotion, isTrue);
  });

  testWidgets('인게임 플레이 화면이 HUD(잉크 팔레트·레벨 번호)를 그린다', (tester) async {
    await pumpScreen(
      tester,
      PlayScreen(
        entry: _entry(1, 1),
        progress: GameProgress(),
        settings: settings,
        audio: const SilentAudioService(),
      ),
    );
    // 잉크 팔레트 바의 석필 라벨 + 대형 레벨 번호.
    expect(find.text('석필'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });
}
