/// 온보딩 문구 생성 단위 테스트 (GDD 7.2) — 목표 조건 4종 + 조사 + 별점 임계.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/ui/onboarding/onboarding_text.dart';

Level _level({
  Map<InkType, int>? optimalInk,
  StarThresholds? thresholds,
  List<FlaskSpec> flasks = const [],
}) =>
    Level(
      meta: LevelMeta(
          id: 1, name: 'L', chapter: 1, difficulty: 1, optimalInk: optimalInk),
      background: 0xFF000000,
      emitters: const [],
      flasks: flasks,
      inkBudget: const {InkType.chalk: 100},
      starThresholds: thresholds,
    );

void main() {
  group('목표 문구 — 조건 4종', () {
    test('개수만 (물질/상태 무관)', () {
      final s = goalLineForFlasks(
          const [FlaskSpec(x: 0, y: 0, w: 8, h: 8, goal: 35)]);
      expect(s, '플라스크를 35만큼 채워라');
    });

    test('물질 지정', () {
      final s = goalLineForFlasks(const [
        FlaskSpec(x: 0, y: 0, w: 8, h: 8, goal: 35, material: Material.prima)
      ]);
      expect(s, '프리마를 플라스크에 35만큼 담아라');
    });

    test('상태 지정', () {
      final s = goalLineForFlasks(const [
        FlaskSpec(
            x: 0,
            y: 0,
            w: 8,
            h: 8,
            goal: 20,
            material: Material.water,
            state: FlaskState.solid)
      ]);
      expect(s, '물을 고체로 20만큼 담아라');
    });

    test('순수(❗) — 재 없이 접두', () {
      final s = goalLineForFlasks(const [
        FlaskSpec(
            x: 0, y: 0, w: 8, h: 8, goal: 35, material: Material.prima, pure: true)
      ]);
      expect(s, '재 없이 프리마를 플라스크에 35만큼 담아라');
    });

    test('다중 플라스크 — 요약', () {
      final s = goalLineForFlasks(const [
        FlaskSpec(x: 0, y: 0, w: 8, h: 8, goal: 10),
        FlaskSpec(x: 0, y: 0, w: 8, h: 8, goal: 20),
      ]);
      expect(s, '플라스크 2곳을 조건대로 채워라');
    });
  });

  group('목적격 조사(을/를)', () {
    test('받침 유무에 따라 을/를', () {
      expect(withEul('프리마'), '프리마를'); // 받침 없음
      expect(withEul('물'), '물을'); // 받침 있음
      expect(withEul('얼음'), '얼음을'); // 받침 있음
      expect(withEul('증기'), '증기를'); // 받침 없음
    });
  });

  group('별점 임계 문구', () {
    test('명시 임계 → 일시정지 임계 1줄', () {
      final level = _level(
          thresholds: const StarThresholds(twoStar: 100, threeStar: 60));
      expect(starThresholdLine(level), '★★ ≤ 100 · ★★★ ≤ 60');
    });

    test('클리어 사용량 1줄 (사용량 + 3성 임계)', () {
      final level = _level(
          thresholds: const StarThresholds(twoStar: 100, threeStar: 60));
      expect(clearUsageLine(level, 80), '사용 80 · ★★★ ≤ 60');
    });

    test('미검증 레벨 — 임계 없음, 사용량만', () {
      final level = _level(); // optimalInk·thresholds 없음
      expect(starThresholdLine(level), isNull);
      expect(clearUsageLine(level, 80), '사용 80');
    });
  });
}
