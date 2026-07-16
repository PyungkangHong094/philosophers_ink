/// 별점 공식 (LEVELS.md 4장 — GDD 5.3보다 구체, 이것을 쓴다). 순수 Dart.
///
/// ★★★ = 사용량 ≤ 최적해 × 1.15 / ★★ = ≤ 최적해 × 1.6 / ★ = 클리어.
/// 최적해(optimalTotal)가 null이면(미검증 레벨) 클리어 시 ★만 부여.
library;

import '../level/level_model.dart';

/// ×1.15, ×1.6 배율을 정수 퍼센트로 (부동소수 오차 방지 — 100*1.15가 114.999…로 내림되는 문제).
/// 매직 넘버 금지 — 여기 한 곳.
const int kThreeStarPercent = 115;
const int kTwoStarPercent = 160;

/// 별점 결과 (0=미클리어, 1~3=별 수).
class StarResult {
  final int stars;
  final bool cleared;

  /// 파생/명시 임계 (UI 표시·검증용). optimalTotal 없으면 null.
  final int? threeStarThreshold;
  final int? twoStarThreshold;

  const StarResult({
    required this.stars,
    required this.cleared,
    this.threeStarThreshold,
    this.twoStarThreshold,
  });
}

/// 별점 계산. [inkUsed] = 소비한 잉크 셀 수 총합.
/// [explicit]이 있으면 그 임계를, 없으면 [optimalTotal]에서 공식 파생.
StarResult computeStars({
  required bool cleared,
  required int inkUsed,
  int? optimalTotal,
  StarThresholds? explicit,
}) {
  if (!cleared) {
    return const StarResult(stars: 0, cleared: false);
  }

  int? three;
  int? two;
  if (explicit != null) {
    three = explicit.threeStar;
    two = explicit.twoStar;
  } else if (optimalTotal != null) {
    // 정수 내림: (총량 × 퍼센트) ~/ 100. 양수라 ~/ = floor.
    three = optimalTotal * kThreeStarPercent ~/ 100;
    two = optimalTotal * kTwoStarPercent ~/ 100;
  }

  // 미검증 레벨(임계 없음) → 클리어 ★1만.
  if (three == null || two == null) {
    return const StarResult(stars: 1, cleared: true);
  }

  final int stars;
  if (inkUsed <= three) {
    stars = 3;
  } else if (inkUsed <= two) {
    stars = 2;
  } else {
    stars = 1;
  }
  return StarResult(
    stars: stars,
    cleared: true,
    threeStarThreshold: three,
    twoStarThreshold: two,
  );
}
