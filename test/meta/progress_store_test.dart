/// ProgressStore 영속 왕복 통합 테스트 (qa-m4 P2) — 진행·설정이 prefs에 저장/복원된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('진행 기록이 prefs에 저장되고 재오픈 시 복원된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ProgressStore(prefs);

    final progress = store.loadProgress();
    progress.record(1, cleared: true, stars: 3);
    progress.record(2, cleared: true, stars: 2);

    // 같은 prefs로 새 스토어를 열어 로드 → 값 복원.
    final reopened = ProgressStore(prefs).loadProgress();
    expect(reopened.starsFor(1), 3);
    expect(reopened.starsFor(2), 2);
    expect(reopened.isCleared(1), isTrue);
    expect(reopened.totalStars, 5);
  });

  test('별점 최고치 갱신이 영속된다 (하락 없음)', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ProgressStore(prefs);
    store.loadProgress().record(1, cleared: true, stars: 1);
    ProgressStore(prefs).loadProgress().record(1, cleared: true, stars: 3);
    // 낮은 별점 재기록은 무시.
    ProgressStore(prefs).loadProgress().record(1, cleared: true, stars: 2);
    expect(ProgressStore(prefs).loadProgress().starsFor(1), 3);
  });

  test('설정(볼륨·사운드·모션)이 저장되고 복원된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsController.fromStore(ProgressStore(prefs));
    s.volume = 0.3;
    s.sound = false;
    s.reducedMotion = true;

    final restored = SettingsController.fromStore(ProgressStore(prefs));
    expect(restored.volume, closeTo(0.3, 1e-9));
    expect(restored.sound, isFalse);
    expect(restored.reducedMotion, isTrue);
    expect(restored.haptics, isTrue, reason: '기본 on 유지');
  });

  test('저장 없던 상태는 기본값', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsController.fromStore(ProgressStore(prefs));
    expect(s.volume, closeTo(0.8, 1e-9));
    expect(s.sound, isTrue);
    expect(s.reducedMotion, isFalse);
    expect(ProgressStore(prefs).loadProgress().totalStars, 0);
  });
}
