/// 수익화 파사드 (GDD 12, 2026-07-22 개편) — 힌트 광고 면제 영속·구매 그랜트·
/// 광고 면제 시 힌트 즉시 승인·스텁 우아한 실패.
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
  void Function()? onAdFreeHintsOwned;
  @override
  Future<void> init() async {}
  @override
  Future<IapOutcome> buyAdFreeHints() async {
    onAdFreeHintsOwned?.call();
    return IapOutcome.purchased;
  }

  @override
  Future<IapOutcome> restore() async {
    onAdFreeHintsOwned?.call();
    return IapOutcome.restored;
  }

  @override
  void dispose() {}
}

/// 리워드 광고를 항상 실패로 돌려 "광고 면제면 광고 경로를 타지 않음"을 증명하는 가짜 광고.
class _FailingAds implements AdsService {
  int hintCalls = 0;
  @override
  bool get isStub => false;
  @override
  Future<void> init() async {}
  @override
  Future<bool> showRewardedForHint() async {
    hintCalls++;
    return false; // 광고 실패 — 면제 소유 시엔 호출 자체가 안 돼야 한다.
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

  test('초기 상태는 광고 면제 미소유', () {
    final m = Monetization.create(store, forceStub: true);
    expect(m.adFreeHints, isFalse);
    expect(m.hintsAvailable, isTrue); // 힌트는 항상 가능(무료는 광고 시청)
  });

  test('구매 그랜트 → adFreeHints true + notify', () async {
    final m = Monetization(
      ads: StubAdsService(),
      iap: _GrantingIap(),
      progressStore: store,
      initialAdFreeHints: false,
    );
    var notified = 0;
    m.addListener(() => notified++);

    final outcome = await m.purchaseAdFreeHints();

    expect(outcome, IapOutcome.purchased);
    expect(m.adFreeHints, isTrue);
    expect(notified, 1);
  });

  test('구매 후 영속 → 새 파사드가 광고 면제 상태로 로드', () async {
    final m = Monetization(
      ads: StubAdsService(),
      iap: _GrantingIap(),
      progressStore: store,
      initialAdFreeHints: false,
    );
    await m.purchaseAdFreeHints();
    expect(store.loadAdsRemoved(), isTrue, reason: 'ProgressStore에 영속(v1 키 호환)');

    // 재부팅 시나리오 — 같은 스토어에서 새 파사드.
    final reloaded = Monetization.create(store, forceStub: true);
    expect(reloaded.adFreeHints, isTrue);
  });

  test('복원 그랜트도 소유를 영속한다', () async {
    final m = Monetization(
      ads: StubAdsService(),
      iap: _GrantingIap(),
      progressStore: store,
      initialAdFreeHints: false,
    );
    final outcome = await m.restorePurchases();
    expect(outcome, IapOutcome.restored);
    expect(m.adFreeHints, isTrue);
    expect(store.loadAdsRemoved(), isTrue);
  });

  test('광고 면제 소유 시 힌트는 광고 경로 없이 즉시 승인', () async {
    final ads = _FailingAds();
    final m = Monetization(
      ads: ads,
      iap: _GrantingIap(),
      progressStore: store,
      initialAdFreeHints: true, // 이미 면제 소유
    );
    expect(await m.requestHint(), isTrue, reason: '면제 소유 → 즉시 승인');
    expect(ads.hintCalls, 0, reason: '광고 서비스를 아예 호출하지 않아야 한다');
  });

  test('미소유 시 힌트는 리워드 광고 결과를 따른다', () async {
    final ads = _FailingAds();
    final m = Monetization(
      ads: ads,
      iap: _GrantingIap(),
      progressStore: store,
      initialAdFreeHints: false,
    );
    expect(await m.requestHint(), isFalse, reason: '광고 실패 → 힌트 거부');
    expect(ads.hintCalls, 1);
  });

  test('스텁은 스토어 미연결로 우아하게 실패한다', () async {
    final m = Monetization.create(store, forceStub: true);
    expect(await m.purchaseAdFreeHints(), IapOutcome.storeUnavailable);
    expect(await m.restorePurchases(), IapOutcome.storeUnavailable);
    expect(m.adFreeHints, isFalse);
  });

  test('스텁 힌트는 즉시 성공한다 (개발 흐름 유지)', () async {
    final m = Monetization.create(store, forceStub: true);
    expect(await m.requestHint(), isTrue);
  });
}
