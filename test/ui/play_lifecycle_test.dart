/// 인게임 오디오 생명주기 회귀 테스트 (P1 후속) — 화면 이탈·앱 백그라운드 시 루프성
/// 재생이 반드시 정지되는지 검증한다. 재생 상태를 추적하는 [_RecordingAudio]로 확인.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 재생 상태를 추적하는 테스트용 오디오. 루프(BGM) 활성 여부와 정지 호출 횟수를 기록한다.
/// (그레인·앰비언트는 원샷이라 정지 대상이 아님 — 유일한 루프는 BGM.)
class _RecordingAudio implements AudioService {
  bool loopActive = false;
  int stopAllCount = 0;
  int stopAmbientCount = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
  @override
  void configure({
    required bool enabled,
    required double volume,
    required bool bgmEnabled,
  }) {}
  @override
  void uiTap() {}
  @override
  void stroke() {}
  @override
  void flaskFill(FlaskState? phase, {double progress = 0}) {}
  @override
  void clearStinger() {}
  @override
  void operatioStinger() {}
  @override
  void fail() {}
  @override
  void phaseTransition(PhaseSfx kind) {}
  @override
  void setAmbience({
    required double particle,
    required double water,
    required double steam,
  }) {}
  @override
  void setBgmChapter(int chapter) {
    loopActive = chapter > 0; // BGM 루프 시작(테스트에선 켜짐만 추적).
  }

  @override
  void stopAmbient() {
    loopActive = false;
    stopAmbientCount++;
  }

  @override
  void stopAll() {
    loopActive = false;
    stopAllCount++;
  }
}

LevelEntry _entry() => LevelEntry(
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

void main() {
  late SettingsController settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsController(ProgressStore(prefs), const {});
  });

  Widget host(AudioService audio) => MaterialApp(
        home: PlayScreen(
          entry: _entry(),
          progress: GameProgress(),
          settings: settings,
          audio: audio,
          onboarding: OnboardingState(),
        ),
      );

  testWidgets('화면 이탈(dispose) 시 루프성 재생이 정지된다', (tester) async {
    final rec = _RecordingAudio();
    await tester.pumpWidget(host(rec));
    await tester.pump(const Duration(milliseconds: 16));

    // PlayScreen init이 setBgmChapter로 BGM 루프를 켰다.
    expect(rec.loopActive, isTrue);

    // PlayScreen을 트리에서 제거 → dispose.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(rec.stopAllCount, greaterThan(0), reason: 'dispose가 stopAll 호출');
    expect(rec.loopActive, isFalse, reason: '루프 정지됨');
  });

  testWidgets('앱 백그라운드 전환 시 루프성 재생이 정지된다', (tester) async {
    final rec = _RecordingAudio();
    await tester.pumpWidget(host(rec));
    await tester.pump(const Duration(milliseconds: 16));

    expect(rec.loopActive, isTrue); // BGM 루프 켜짐

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(rec.stopAllCount, greaterThan(0), reason: '백그라운드가 stopAll 호출');
    expect(rec.loopActive, isFalse);
    await tester.pumpWidget(const SizedBox.shrink()); // 온보딩 타이머 정리.
  });
}
