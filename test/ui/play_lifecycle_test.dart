/// 인게임 오디오 생명주기 회귀 테스트 (P1 후속) — 화면 이탈·앱 백그라운드 시 루프성
/// 재생이 반드시 정지되는지 검증한다. 재생 상태를 추적하는 [_RecordingAudio]로 확인.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/progress.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/game/play_screen.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 재생 상태를 추적하는 테스트용 오디오. 루프 활성 여부와 정지 호출 횟수를 기록한다.
class _RecordingAudio implements AudioService {
  bool loopActive = false;
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
  void flaskFill(FlaskState? phase) {}
  @override
  void clearStinger() {}
  @override
  void operatioStinger() {}
  @override
  void fail() {}
  @override
  void setAmbientDensity(double normalized) {
    if (normalized > 0) loopActive = true;
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
        ),
      );

  testWidgets('화면 이탈(dispose) 시 루프성 재생이 정지된다', (tester) async {
    final rec = _RecordingAudio();
    await tester.pumpWidget(host(rec));
    await tester.pump(const Duration(milliseconds: 16));

    // 루프가 재생 중이라고 가정.
    rec.setAmbientDensity(1.0);
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

    rec.setAmbientDensity(1.0);
    expect(rec.loopActive, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(rec.stopAllCount, greaterThan(0), reason: '백그라운드가 stopAll 호출');
    expect(rec.loopActive, isFalse);
  });
}
