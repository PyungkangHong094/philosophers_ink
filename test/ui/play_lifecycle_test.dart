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

/// 정지 호출 횟수를 기록하는 테스트용 오디오. BGM 제거 후 지속 루프는 없지만, 생명주기
/// 계약(화면 이탈·백그라운드에서 stopAll 호출)은 미래 BGM 대비 유지된다.
class _RecordingAudio implements AudioService {
  int stopAllCount = 0;
  int stopAmbientCount = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
  @override
  void configure({required bool enabled, required double volume}) {}
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
  void stopAmbient() {
    stopAmbientCount++;
  }

  @override
  void stopAll() {
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

  testWidgets('화면 이탈(dispose) 시 stopAll이 호출된다 (생명주기 계약)', (tester) async {
    final rec = _RecordingAudio();
    await tester.pumpWidget(host(rec));
    await tester.pump(const Duration(milliseconds: 16));

    // PlayScreen을 트리에서 제거 → dispose.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(rec.stopAllCount, greaterThan(0), reason: 'dispose가 stopAll 호출');
  });

  testWidgets('앱 백그라운드 전환 시 stopAll이 호출된다', (tester) async {
    final rec = _RecordingAudio();
    await tester.pumpWidget(host(rec));
    await tester.pump(const Duration(milliseconds: 16));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(rec.stopAllCount, greaterThan(0), reason: '백그라운드가 stopAll 호출');
    await tester.pumpWidget(const SizedBox.shrink()); // 온보딩 타이머 정리.
  });
}
