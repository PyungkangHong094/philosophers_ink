import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/star_rating.dart';
import 'package:philosophers_ink/level/level_model.dart';

void main() {
  group('별점 공식 (LEVELS 4장)', () {
    test('미클리어는 0성', () {
      final r = computeStars(cleared: false, inkUsed: 10, optimalTotal: 100);
      expect(r.stars, 0);
      expect(r.cleared, isFalse);
    });

    test('최적해 100 → 임계 115/160 파생', () {
      final r = computeStars(cleared: true, inkUsed: 100, optimalTotal: 100);
      expect(r.threeStarThreshold, 115); // floor(100*1.15)
      expect(r.twoStarThreshold, 160); // floor(100*1.6)
      expect(r.stars, 3);
    });

    test('경계값 — ≤115=3성, 116=2성, ≤160=2성, 161=1성', () {
      expect(computeStars(cleared: true, inkUsed: 115, optimalTotal: 100).stars, 3);
      expect(computeStars(cleared: true, inkUsed: 116, optimalTotal: 100).stars, 2);
      expect(computeStars(cleared: true, inkUsed: 160, optimalTotal: 100).stars, 2);
      expect(computeStars(cleared: true, inkUsed: 161, optimalTotal: 100).stars, 1);
    });

    test('최적해 null(미검증)이면 클리어 시 ★만', () {
      final r = computeStars(cleared: true, inkUsed: 5, optimalTotal: null);
      expect(r.stars, 1);
      expect(r.threeStarThreshold, isNull);
    });

    test('명시 임계가 파생보다 우선', () {
      final r = computeStars(
        cleared: true,
        inkUsed: 50,
        optimalTotal: 100,
        explicit: const StarThresholds(twoStar: 80, threeStar: 40),
      );
      expect(r.threeStarThreshold, 40);
      expect(r.twoStarThreshold, 80);
      expect(r.stars, 2, reason: '50 > 40, ≤ 80');
    });
  });
}
