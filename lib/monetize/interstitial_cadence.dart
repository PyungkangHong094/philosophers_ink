/// 전면광고 빈도 게이트 (GDD 12) — 순수 로직, SDK 비의존이라 단위 테스트 대상.
///
/// 클리어마다 [onLevelClearedShouldShow]를 호출한다. 정책([AdsPolicy]) 통과 시에만 true를
/// 돌려주고 내부 카운터를 리셋한다. 실제 광고 로드/표시는 호출자([AdsService])가 담당한다.
library;

import 'monetize_constants.dart';

class InterstitialCadence {
  final int minClears;
  final Duration cooldown;
  final bool useGrace;

  /// 마지막 노출 이후 클리어 횟수.
  int _clearsSinceShown = 0;

  /// 마지막으로 true를 반환(=노출)한 시각. null이면 아직 없음.
  DateTime? _lastShown;

  /// 첫 세션 유예를 이미 소진했는가.
  bool _graceConsumed = false;

  InterstitialCadence({
    this.minClears = AdsPolicy.minClearsBetweenInterstitials,
    this.cooldown = AdsPolicy.interstitialCooldown,
    this.useGrace = AdsPolicy.firstSessionGrace,
  });

  /// 마지막 노출 이후 클리어 수(관측용).
  int get clearsSinceShown => _clearsSinceShown;

  /// 레벨 클리어 시 호출. [now] 기준으로 전면광고를 띄워야 하면 true(+카운터 리셋).
  ///
  /// 순서: (1) 최소 클리어 간격 미달이면 false. (2) 세션 첫 자격 도달은 유예로 건너뜀
  /// (카운터만 리셋). (3) 쿨다운 미경과면 false. (4) 통과 → 노출 시각 기록 후 true.
  bool onLevelClearedShouldShow(DateTime now) {
    _clearsSinceShown++;
    if (_clearsSinceShown < minClears) return false;

    if (useGrace && !_graceConsumed) {
      _graceConsumed = true;
      _clearsSinceShown = 0;
      return false;
    }

    final last = _lastShown;
    if (last != null && now.difference(last) < cooldown) return false;

    _lastShown = now;
    _clearsSinceShown = 0;
    return true;
  }
}
