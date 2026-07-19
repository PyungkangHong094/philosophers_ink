/// 광고 서비스 추상화 (GDD 12) — 전면광고(클리어 사이)·리워드 광고(힌트).
///
/// [AdsService]는 인터페이스, [StubAdsService]는 개발/시뮬레이터/테스트용 무광고 스텁,
/// [GoogleAdsService]는 google_mobile_ads 실구현이다. 앱은 [AdsService.create]로 환경에
/// 맞춰 하나를 고른다(kDebugMode=스텁 — 개발 흐름 보호). 빈도 정책은 [InterstitialCadence]
/// (순수 로직)에 위임한다. 광고 제거 구매 상태([adsRemoved])면 전면광고를 내지 않는다.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'interstitial_cadence.dart';
import 'monetize_constants.dart';

abstract class AdsService {
  /// 스텁이면 true(광고 미표시). UI가 "개발 중 광고 없음" 판단에 쓰지 않고, 주로 테스트용.
  bool get isStub;

  /// 광고 제거 단품 구매 여부. true면 전면광고를 내지 않는다(리워드 힌트는 무관).
  bool adsRemoved = false;

  /// SDK 초기화 + 첫 광고 프리로드. 실패해도 게임을 막지 않는다(내부 무음화).
  Future<void> init();

  /// 레벨 클리어 시 호출 — 빈도 정책 통과 + 미제거 시에만 전면광고. 아니면 no-op.
  Future<void> onLevelCleared();

  /// 리워드 광고(힌트). 보상 획득 시 true. 스텁은 즉시 true(개발 중 힌트 흐름 유지).
  Future<bool> showRewardedForHint();

  void dispose();

  /// 환경에 맞는 구현 선택. [forceStub]가 true(기본: kDebugMode)면 스텁.
  factory AdsService.create({bool? forceStub}) {
    final stub = forceStub ?? kDebugMode;
    return stub ? StubAdsService() : GoogleAdsService();
  }
}

/// 무광고 스텁 — 개발/시뮬레이터/테스트. 전면광고 no-op, 리워드는 즉시 성공.
class StubAdsService implements AdsService {
  @override
  bool get isStub => true;

  @override
  bool adsRemoved = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> onLevelCleared() async {}

  @override
  Future<bool> showRewardedForHint() async => true;

  @override
  void dispose() {}
}

/// google_mobile_ads 실구현. 전면광고는 소진 즉시 다음 것을 프리로드한다.
class GoogleAdsService implements AdsService {
  final InterstitialCadence _cadence = InterstitialCadence();

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _initialized = false;

  @override
  bool get isStub => false;

  @override
  bool adsRemoved = false;

  String get _interstitialUnit => Platform.isIOS
      ? AdUnits.iosInterstitial
      : AdUnits.androidInterstitial;

  String get _rewardedUnit =>
      Platform.isIOS ? AdUnits.iosRewarded : AdUnits.androidRewarded;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      if (kDebugMode) debugPrint('[Ads] 초기화 실패(무음화): $e');
    }
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  @override
  Future<void> onLevelCleared() async {
    if (adsRemoved) return;
    if (!_cadence.onLevelClearedShouldShow(DateTime.now())) return;
    final ad = _interstitial;
    if (ad == null) return; // 아직 미로드 — 이번은 조용히 건너뛴다.
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  @override
  Future<bool> showRewardedForHint() async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded(); // 다음 시도를 위해 프리로드.
      return false;
    }
    _rewarded = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return completer.future;
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
  }
}
