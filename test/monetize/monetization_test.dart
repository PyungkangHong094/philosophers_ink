/// 수익화 파사드 (GDD 12) — 광고 제거 영속·구매 그랜트·스텁 우아한 실패.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/meta/progress_store.dart';
import 'package:philosophers_ink/monetize/ads_service.dart';
import 'package:philosophers_ink/monetize/iap_service.dart';
import 'package:philosophers_ink/monetize/monetization.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 구매 시 즉시 소유를 통지하는 가짜 IAP (실 스토어 대체).
class _GrantingIap implements IapService {
  @override
  bool get isStub => true;
  @override
  void Function()? onRemoveAdsOwned;
  @override
  Future<void> init() async {}
  @override
  Future<IapOutcome> buyRemoveAds() async {
    onRemoveAdsOwned?.call();
    return IapOutcome.purchased;
  }

  @override
  Future<IapOutcome> restore() async {
    onRemoveAdsOwned?.call();
    return IapOutcome.restored;
  }

  @override
  void dispose() {}
}

void main() {
  late ProgressStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProgressStore(await SharedPreferences.getInstance());
  });

  test('초기 상태는 광고 미제거', () {
    final m = Monetization.create(store, forceStub: true);
    expect(m.adsRemoved, isFalse);
    expect(m.hintsAvailable, isTrue); // 힌트는 IAP 무관 항상 가능
  });

  test('구매 그랜트 → adsRemoved true + 광고 게이트 전파 + notify', () async {
    final ads = StubAdsService();
    final m = Monetization(
      ads: ads,
      iap: _GrantingIap(),
      progressStore: store,
      initialAdsRemoved: false,
    );
    var notified = 0;
    m.addListener(() => notified++);

    final outcome = await m.purchaseRemoveAds();

    expect(outcome, IapOutcome.purchased);
    expect(m.adsRemoved, isTrue);
    expect(ads.adsRemoved, isTrue, reason: '광고 서비스에 제거 상태 전파');
    expect(notified, 1);
  });

  test('구매 후 영속 → 새 파사드가 광고 제거 상태로 로드', () async {
    final m = Monetization(
      ads: StubAdsService(),
      iap: _GrantingIap(),
      progressStore: store,
      initialAdsRemoved: false,
    );
    await m.purchaseRemoveAds();
    expect(store.loadAdsRemoved(), isTrue, reason: 'ProgressStore에 영속');

    // 재부팅 시나리오 — 같은 스토어에서 새 파사드.
    final reloaded = Monetization.create(store, forceStub: true);
    expect(reloaded.adsRemoved, isTrue);
  });

  test('복원 그랜트도 소유를 영속한다', () async {
    final m = Monetization(
      ads: StubAdsService(),
      iap: _GrantingIap(),
      progressStore: store,
      initialAdsRemoved: false,
    );
    final outcome = await m.restorePurchases();
    expect(outcome, IapOutcome.restored);
    expect(m.adsRemoved, isTrue);
    expect(store.loadAdsRemoved(), isTrue);
  });

  test('스텁은 스토어 미연결로 우아하게 실패한다', () async {
    final m = Monetization.create(store, forceStub: true);
    expect(await m.purchaseRemoveAds(), IapOutcome.storeUnavailable);
    expect(await m.restorePurchases(), IapOutcome.storeUnavailable);
    expect(m.adsRemoved, isFalse);
  });

  test('스텁 힌트는 즉시 성공한다 (개발 흐름 유지)', () async {
    final m = Monetization.create(store, forceStub: true);
    expect(await m.requestHint(), isTrue);
  });
}
