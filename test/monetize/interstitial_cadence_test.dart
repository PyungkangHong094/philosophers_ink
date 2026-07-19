/// 전면광고 빈도 게이트 로직 (GDD 12) — 최소 클리어 간격·첫 세션 유예·쿨다운.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/monetize/interstitial_cadence.dart';

void main() {
  final t0 = DateTime(2026, 7, 20, 12, 0, 0);

  group('최소 클리어 간격', () {
    test('간격 미달이면 노출하지 않는다', () {
      final c = InterstitialCadence(
          minClears: 3, cooldown: Duration.zero, useGrace: false);
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 1
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 2
      expect(c.onLevelClearedShouldShow(t0), isTrue); // 3 — 도달
    });

    test('노출 후 카운터가 리셋된다', () {
      final c = InterstitialCadence(
          minClears: 2, cooldown: Duration.zero, useGrace: false);
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 1
      expect(c.onLevelClearedShouldShow(t0), isTrue); // 2 — 노출
      expect(c.clearsSinceShown, 0);
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 다시 1
      expect(c.onLevelClearedShouldShow(t0), isTrue); // 2 — 재노출
    });
  });

  group('첫 세션 유예', () {
    test('세션 첫 자격 도달은 유예로 건너뛴다', () {
      final c = InterstitialCadence(
          minClears: 2, cooldown: Duration.zero, useGrace: true);
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 1
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 2 — 자격이나 유예 소진
      expect(c.clearsSinceShown, 0); // 유예 후 카운터 리셋
      expect(c.onLevelClearedShouldShow(t0), isFalse); // 1
      expect(c.onLevelClearedShouldShow(t0), isTrue); // 2 — 유예 소진 후 첫 노출
    });
  });

  group('쿨다운', () {
    test('쿨다운 미경과면 간격을 채워도 노출하지 않는다', () {
      final c = InterstitialCadence(
          minClears: 1,
          cooldown: const Duration(seconds: 90),
          useGrace: false);
      expect(c.onLevelClearedShouldShow(t0), isTrue); // 첫 노출
      // 60초 뒤 — 쿨다운(90s) 미경과.
      expect(
          c.onLevelClearedShouldShow(t0.add(const Duration(seconds: 60))),
          isFalse);
      // 91초 뒤 — 쿨다운 경과.
      expect(
          c.onLevelClearedShouldShow(t0.add(const Duration(seconds: 91))),
          isTrue);
    });
  });
}
