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
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/ui/app.dart';
import 'package:philosophers_ink/ui/game/ink_palette_bar.dart';
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
          onboarding: OnboardingState(),
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
    expect(find.text('화면을 터치해 시작'), findsOneWidget);
  });

  testWidgets('타이틀 탭 → 챕터 선택으로 내비게이션 (푸시 라우트에서 InkServices 접근 회귀)',
      (tester) async {
    // 실제 앱 구조 그대로: InkServices가 MaterialApp(=Navigator) **위**.
    // 아래에 두면 푸시된 라우트가 InkServices 바깥이 되어 of()가 단언 실패한다.
    await tester.pumpWidget(
      InkServices(
        settings: settings,
        progress: GameProgress(),
        catalog: LevelCatalog([_entry(1, 1)]),
        audio: const SilentAudioService(),
        onboarding: OnboardingState(),
        child: const MaterialApp(home: TitleScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('화면을 터치해 시작'));
    // 전환 애니메이션 소화 (타이틀 반복 애니메이션 때문에 pumpAndSettle 금지).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(ChapterSelectScreen), findsOneWidget);
  });

  testWidgets('타이틀이 좁은 화면에서도 수평 중앙 정렬된다 (좌측 수축 회귀)', (tester) async {
    await pumpScreen(tester, const TitleScreen());
    final screenWidth = tester.getSize(find.byType(TitleScreen)).width;
    final inkCenter = tester.getCenter(find.text('INK'));
    expect((inkCenter.dx - screenWidth / 2).abs(), lessThan(1.0),
        reason: 'INK 로고가 화면 수평 중앙에 있어야 한다 (dx=${inkCenter.dx}, '
            '기대=${screenWidth / 2})');
  });

  testWidgets('챕터 선택이 4챕터 라틴명을 그리고 잠금 챕터를 표시한다', (tester) async {
    final catalog = LevelCatalog([_entry(1, 1)]);
    await pumpScreen(tester, const ChapterSelectScreen(), catalog: catalog);
    expect(find.text('NIGREDO'), findsOneWidget);
    expect(find.text('RUBEDO'), findsOneWidget);
    // 챕터 2는 콘텐츠 없고 잠김 → 해금 안내 노출.
    expect(find.textContaining('완료하면 해금'), findsWidgets);
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
        onboarding: OnboardingState(),
      ),
    );
    // 잉크 팔레트(우측 상단 컴팩트) + 대형 레벨 번호.
    expect(find.byType(InkPaletteBar), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    // 온보딩 타이머 정리 — 위젯 제거로 dispose(타이머 취소).
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('플레이 화면 콘텐츠가 0 크기로 붕괴하지 않는다 (실기기 블랙스크린 회귀)',
      (tester) async {
    // 존재 검사만으로는 못 잡는다 — 0×0 위젯도 find는 성공한다. 크기를 단언한다.
    // (body Stack 자식이 전부 Positioned라 fit 미지정 시 느슨한 제약에서 0×0 붕괴했었다.)
    await pumpScreen(
      tester,
      PlayScreen(
        entry: _entry(1, 1),
        progress: GameProgress(),
        settings: settings,
        audio: const SilentAudioService(),
        onboarding: OnboardingState(),
      ),
    );
    final screen = tester.getSize(find.byType(PlayScreen));
    final palette = tester.getSize(find.byType(InkPaletteBar));
    expect(palette.width, greaterThan(0), reason: 'HUD 팔레트가 실제 크기를 가져야 한다');
    expect(palette.height, greaterThan(0));
    final stack = tester.renderObject<RenderBox>(
      find
          .descendant(of: find.byType(PlayScreen), matching: find.byType(Stack))
          .first,
    );
    expect(stack.size.width, screen.width,
        reason: '플레이 화면 body Stack은 화면 폭을 가득 채워야 한다 (0×0 붕괴 회귀)');
    expect(stack.size.height, screen.height,
        reason: '플레이 화면 body Stack은 화면 높이를 가득 채워야 한다');
    await tester.pumpWidget(const SizedBox.shrink()); // 온보딩 타이머 정리.
  });
}
