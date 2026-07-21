/// 광고 서비스 추상화 (GDD 12) — **보상형 광고(힌트)만**.
///
/// 수익화 개편(2026-07-22): 전면광고를 폐지하고 opt-in 리워드 광고(힌트 시청) 하나만
/// 남긴다. 강제 광고가 없으므로 광고 빈도 정책·클리어 사이 노출이 전부 사라졌다.
///
/// [AdsService]는 인터페이스, [StubAdsService]는 개발/시뮬레이터/테스트용 무광고 스텁,
/// [GoogleAdsService]는 google_mobile_ads 실구현이다. 앱은 [AdsService.create]로 환경에
/// 맞춰 하나를 고른다(kDebugMode=스텁 — 개발 흐름 보호).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetize_constants.dart';

abstract class AdsService {
  /// 스텁이면 true(광고 미표시). 주로 테스트용.
  bool get isStub;

  /// SDK 초기화 + 첫 리워드 광고 프리로드. 실패해도 게임을 막지 않는다(내부 무음화).
  Future<void> init();

  /// 리워드 광고(힌트). 보상 획득 시 true. 스텁은 즉시 true(개발 중 힌트 흐름 유지).
  Future<bool> showRewardedForHint();

  void dispose();

  /// 환경에 맞는 구현 선택. [forceStub]가 true(기본: kDebugMode)면 스텁.
  factory AdsService.create({bool? forceStub}) {
    final stub = forceStub ?? kDebugMode;
    return stub ? StubAdsService() : GoogleAdsService();
  }
}

/// 무광고 스텁 — 개발/시뮬레이터/테스트. 리워드는 즉시 성공.
class StubAdsService implements AdsService {
  @override
  bool get isStub => true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> showRewardedForHint() async => true;

  @override
  void dispose() {}
}

/// google_mobile_ads 실구현 — 리워드 광고(힌트)만. 소진 즉시 다음 것을 프리로드한다.
class GoogleAdsService implements AdsService {
  RewardedAd? _rewarded;
  bool _initialized = false;

  @override
  bool get isStub => false;

  String get _rewardedUnit =>
      Platform.isIOS ? AdUnits.iosRewarded : AdUnits.androidRewarded;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
      _loadRewarded();
    } catch (e) {
      if (kDebugMode) debugPrint('[Ads] 초기화 실패(무음화): $e');
    }
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
    _rewarded?.dispose();
    _rewarded = null;
  }
}
