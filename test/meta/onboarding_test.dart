/// 온보딩 상태 단위 + 영속 왕복 테스트 (GDD 7.2) — 1회 노출·리셋·prefs 저장/복원.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/meta/onboarding.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OnboardingState', () {
    test('markSeenOnce는 처음만 true, 이후 false', () {
      final ob = OnboardingState();
      expect(ob.markSeenOnce(OnboardingKey.stroke), isTrue);
      expect(ob.hasSeen(OnboardingKey.stroke), isTrue);
      expect(ob.markSeenOnce(OnboardingKey.stroke), isFalse);
    });

    test('reset이 전부 초기화 → 다시 노출 가능', () {
      final ob = OnboardingState();
      ob.markSeenOnce(OnboardingKey.stroke);
      ob.markSeenOnce(OnboardingKey.firstClear);
      ob.reset();
      expect(ob.hasSeen(OnboardingKey.stroke), isFalse);
      expect(ob.markSeenOnce(OnboardingKey.stroke), isTrue);
    });

    test('onChanged 훅이 변경마다 호출 (영속화)', () {
      var saves = 0;
      final ob = OnboardingState(onChanged: (_) => saves++);
      ob.markSeenOnce(OnboardingKey.stroke);
      ob.markSeenOnce(OnboardingKey.gauge);
      expect(saves, 2);
      ob.markSeenOnce(OnboardingKey.stroke); // 중복 → 저장 없음
      expect(saves, 2);
    });

    test('JSON 리스트 왕복', () {
      final ob = OnboardingState();
      ob.markSeenOnce(OnboardingKey.stroke);
      ob.markSeenOnce(OnboardingKey.gravity);
      final restored = OnboardingState.fromJsonList(ob.toJsonList());
      expect(restored.hasSeen(OnboardingKey.stroke), isTrue);
      expect(restored.hasSeen(OnboardingKey.gravity), isTrue);
      expect(restored.hasSeen(OnboardingKey.firstClear), isFalse);
    });
  });

  group('ProgressStore 온보딩 영속', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('노출 이력이 prefs에 저장되고 재오픈 시 복원', () async {
      final prefs = await SharedPreferences.getInstance();
      ProgressStore(prefs).loadOnboarding().markSeenOnce(OnboardingKey.firstClear);
      final reopened = ProgressStore(prefs).loadOnboarding();
      expect(reopened.hasSeen(OnboardingKey.firstClear), isTrue);
    });

    test('reset도 영속된다', () async {
      final prefs = await SharedPreferences.getInstance();
      ProgressStore(prefs).loadOnboarding().markSeenOnce(OnboardingKey.stroke);
      ProgressStore(prefs).loadOnboarding().reset();
      expect(
          ProgressStore(prefs).loadOnboarding().hasSeen(OnboardingKey.stroke),
          isFalse);
    });
  });
}
