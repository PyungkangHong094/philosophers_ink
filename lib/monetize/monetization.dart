/// 수익화 파사드 (GDD 12) — 보상형 광고([AdsService]) + IAP([IapService]).
///
/// 수익화 개편(2026-07-22): 전면광고 폐지, opt-in 리워드 광고(힌트)만. 유료 항목은
/// "힌트 광고 없이 보기" 단품 하나뿐이며, 소유([adFreeHints]) 시 힌트가 광고 시청 없이
/// 즉시 열린다. 소유 상태는 [ProgressStore]에 영속되고 구매·복원 시 IAP 콜백으로 갱신된다.
/// UI는 이 파사드 하나만 본다. [InkServices]로 위젯 트리에 주입한다.
library;

import 'package:flutter/foundation.dart';

import '../meta/progress_store.dart';
import 'ads_service.dart';
import 'iap_service.dart';

class Monetization extends ChangeNotifier {
  final AdsService ads;
  final IapService iap;
  final ProgressStore _store;

  bool _adFreeHints;

  Monetization({
    required this.ads,
    required this.iap,
    required ProgressStore progressStore,
    required bool initialAdFreeHints,
  })  : _store = progressStore,
        _adFreeHints = initialAdFreeHints {
    iap.onAdFreeHintsOwned = _grantAdFreeHints;
  }

  /// 환경(kDebugMode=스텁)에 맞춰 서비스를 골라 조립한다. [forceStub]로 강제 가능(테스트).
  factory Monetization.create(ProgressStore store, {bool? forceStub}) {
    return Monetization(
      ads: AdsService.create(forceStub: forceStub),
      iap: IapService.create(forceStub: forceStub),
      progressStore: store,
      initialAdFreeHints: store.loadAdsRemoved(),
    );
  }

  /// SDK 초기화(광고 프리로드·스토어 연결). 실패해도 게임을 막지 않는다.
  Future<void> init() async {
    await ads.init();
    await iap.init();
  }

  /// "힌트 광고 없이 보기" 단품 소유 여부.
  bool get adFreeHints => _adFreeHints;

  /// 힌트 사용 가능 여부 — 항상 가능(무료는 광고 시청, 소유 시 즉시).
  bool get hintsAvailable => true;

  /// 힌트 요청. 광고 면제 소유 시 광고 없이 즉시 승인, 아니면 리워드 광고 시청 결과.
  Future<bool> requestHint() async {
    if (_adFreeHints) return true;
    return ads.showRewardedForHint();
  }

  /// "힌트 광고 없이 보기" 구매 시도.
  Future<IapOutcome> purchaseAdFreeHints() => iap.buyAdFreeHints();

  /// 구매 복원 시도.
  Future<IapOutcome> restorePurchases() => iap.restore();

  void _grantAdFreeHints() {
    if (_adFreeHints) return;
    _adFreeHints = true;
    _store.saveAdsRemoved(true);
    notifyListeners();
  }

  @override
  void dispose() {
    ads.dispose();
    iap.dispose();
    super.dispose();
  }
}
