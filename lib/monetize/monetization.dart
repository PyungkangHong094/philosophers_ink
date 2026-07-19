/// 수익화 파사드 (GDD 12) — 광고([AdsService]) + IAP([IapService]) + 광고 제거 영속 상태.
///
/// UI는 이 파사드 하나만 본다. 광고 제거 소유([adsRemoved])는 [ProgressStore]에 영속하며,
/// 구매·복원 시 IAP 콜백으로 갱신된다. 전면광고는 미제거 시에만, 리워드 힌트는 항상 가능하다
/// (IAP 무관 — GDD 12). [InkServices]로 위젯 트리에 주입한다.
library;

import 'package:flutter/foundation.dart';

import '../meta/progress_store.dart';
import 'ads_service.dart';
import 'iap_service.dart';

class Monetization extends ChangeNotifier {
  final AdsService ads;
  final IapService iap;
  final ProgressStore _store;

  bool _adsRemoved;

  Monetization({
    required this.ads,
    required this.iap,
    required ProgressStore progressStore,
    required bool initialAdsRemoved,
  })  : _store = progressStore,
        _adsRemoved = initialAdsRemoved {
    ads.adsRemoved = _adsRemoved;
    iap.onRemoveAdsOwned = _grantRemoveAds;
  }

  /// 환경(kDebugMode=스텁)에 맞춰 서비스를 골라 조립한다. [forceStub]로 강제 가능(테스트).
  factory Monetization.create(ProgressStore store, {bool? forceStub}) {
    return Monetization(
      ads: AdsService.create(forceStub: forceStub),
      iap: IapService.create(forceStub: forceStub),
      progressStore: store,
      initialAdsRemoved: store.loadAdsRemoved(),
    );
  }

  /// SDK 초기화(광고 프리로드·스토어 연결). 실패해도 게임을 막지 않는다.
  Future<void> init() async {
    await ads.init();
    await iap.init();
  }

  /// 광고 제거 단품 소유 여부.
  bool get adsRemoved => _adsRemoved;

  /// 힌트(리워드 광고) 사용 가능 여부 — IAP 무관, 항상 가능(GDD 12).
  bool get hintsAvailable => true;

  /// 레벨 클리어 후 호출 — 빈도 정책 통과 시 전면광고. 광고 제거 시 no-op.
  Future<void> onLevelCleared() => ads.onLevelCleared();

  /// 힌트 요청(리워드 광고). 보상 획득 시 true.
  Future<bool> requestHint() => ads.showRewardedForHint();

  /// 광고 제거 구매 시도.
  Future<IapOutcome> purchaseRemoveAds() => iap.buyRemoveAds();

  /// 구매 복원 시도.
  Future<IapOutcome> restorePurchases() => iap.restore();

  void _grantRemoveAds() {
    if (_adsRemoved) return;
    _adsRemoved = true;
    ads.adsRemoved = true;
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
