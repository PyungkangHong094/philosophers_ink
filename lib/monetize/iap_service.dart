/// 인앱 구매 서비스 (GDD 12) — 광고 제거 단품 + 구매 복원.
///
/// [IapService]는 인터페이스, [StubIapService]는 개발/시뮬레이터/테스트용(스토어 미연결
/// 우아한 실패), [StoreIapService]는 in_app_purchase 실구현이다. 구매/복원 확정은
/// [onRemoveAdsOwned] 콜백으로 알린다 — 영속·광고 게이팅은 상위([Monetization])가 처리한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetize_constants.dart';

/// 구매/복원 시도의 결과 (UI 피드백 분기용).
enum IapOutcome {
  /// 신규 구매 완료.
  purchased,

  /// 복원으로 소유 확인.
  restored,

  /// 복원했으나 소유 항목 없음.
  nothingToRestore,

  /// 스토어 미연결(시뮬레이터·미로그인 등) — 우아한 실패.
  storeUnavailable,

  /// 사용자 취소.
  canceled,

  /// 기타 오류.
  error,
}

abstract class IapService {
  bool get isStub;

  /// 광고 제거 소유 확정 콜백(구매·복원). 상위가 영속 + 광고 비활성 처리.
  void Function()? onRemoveAdsOwned;

  Future<void> init();

  /// 광고 제거 단품 구매.
  Future<IapOutcome> buyRemoveAds();

  /// 구매 복원.
  Future<IapOutcome> restore();

  void dispose();

  factory IapService.create({bool? forceStub}) {
    final stub = forceStub ?? kDebugMode;
    return stub ? StubIapService() : StoreIapService();
  }
}

/// 스토어 미연결 스텁 — 개발/시뮬레이터/테스트. 구매·복원 모두 우아한 실패.
class StubIapService implements IapService {
  @override
  bool get isStub => true;

  @override
  void Function()? onRemoveAdsOwned;

  @override
  Future<void> init() async {}

  @override
  Future<IapOutcome> buyRemoveAds() async => IapOutcome.storeUnavailable;

  @override
  Future<IapOutcome> restore() async => IapOutcome.storeUnavailable;

  @override
  void dispose() {}
}

/// in_app_purchase 실구현.
class StoreIapService implements IapService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _available = false;

  /// 진행 중인 구매/복원 시도를 대기하는 completer (스트림이 결과를 완결).
  Completer<IapOutcome>? _pending;
  bool _sawOwnershipInRestore = false;

  @override
  bool get isStub => false;

  @override
  void Function()? onRemoveAdsOwned;

  @override
  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] 초기화 실패: $e');
      _available = false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == IapProducts.removeAds) {
            onRemoveAdsOwned?.call();
            _sawOwnershipInRestore = true;
            _complete(p.status == PurchaseStatus.restored
                ? IapOutcome.restored
                : IapOutcome.purchased);
          }
        case PurchaseStatus.error:
          _complete(IapOutcome.error);
        case PurchaseStatus.canceled:
          _complete(IapOutcome.canceled);
        case PurchaseStatus.pending:
          break; // 대기 — 결과는 후속 이벤트로.
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void _complete(IapOutcome outcome) {
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete(outcome);
  }

  @override
  Future<IapOutcome> buyRemoveAds() async {
    if (!_available) return IapOutcome.storeUnavailable;
    try {
      final resp =
          await _iap.queryProductDetails(IapProducts.all);
      final pd = resp.productDetails
          .where((d) => d.id == IapProducts.removeAds)
          .cast<ProductDetails?>()
          .firstWhere((_) => true, orElse: () => null);
      if (pd == null) return IapOutcome.error;
      _pending = Completer<IapOutcome>();
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: pd));
      return _pending!.future
          .timeout(const Duration(minutes: 5), onTimeout: () => IapOutcome.error);
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] 구매 실패: $e');
      return IapOutcome.error;
    }
  }

  @override
  Future<IapOutcome> restore() async {
    if (!_available) return IapOutcome.storeUnavailable;
    try {
      _sawOwnershipInRestore = false;
      _pending = Completer<IapOutcome>();
      await _iap.restorePurchases();
      // 복원은 소유 항목이 있으면 스트림이 restored로 완결한다. 없으면 타임아웃 →
      // 소유 관측 여부로 판정(관측 없으면 복원할 것 없음).
      return _pending!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => _sawOwnershipInRestore
            ? IapOutcome.restored
            : IapOutcome.nothingToRestore,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] 복원 실패: $e');
      return IapOutcome.error;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
