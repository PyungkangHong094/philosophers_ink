/// 수익화 상수 (GDD 12장) — 광고 빈도 정책·앱/광고 단위 ID·IAP 상품 ID의 단일 소스.
///
/// 위젯·서비스 코드에 매직 넘버·문자열 ID 직접 기입 금지 — 전부 여기서 참조한다.
/// 현재 광고 ID는 전부 **Google 공식 테스트 ID**다. 실 출시 전 아래 `TODO(release)`
/// 표시가 붙은 상수를 실제 AdMob 앱/광고 단위 ID와 IAP 상품 ID로 교체한다.
/// (교체 위치 목록: _workspace/m6_monetize_20260720.md.)
library;

/// 전면광고 빈도 정책 (GDD 12 "연속 노출 방지 쿨다운").
///
/// 노출 조건: 마지막 노출 이후 [minClearsBetweenInterstitials]회 이상 클리어했고,
/// 마지막 노출로부터 [interstitialCooldown] 이상 지났을 때만. 앱 세션의 첫 자격 도달은
/// [firstSessionGrace]로 건너뛴다(첫인상 보호 — GDD 12 정책).
abstract final class AdsPolicy {
  /// 전면광고 사이 최소 클리어 간격.
  static const int minClearsBetweenInterstitials = 3;

  /// 전면광고 연속 노출 방지 쿨다운.
  static const Duration interstitialCooldown = Duration(seconds: 90);

  /// 첫 세션 유예 — 세션 내 첫 자격 도달 1회는 광고 없이 넘긴다.
  static const bool firstSessionGrace = true;
}

/// AdMob 앱/광고 단위 ID. 현재 전부 Google 공식 테스트 ID.
///
/// 테스트 ID 출처: https://developers.google.com/admob/{android,ios}/test-ads
abstract final class AdUnits {
  // 앱 ID — AndroidManifest meta-data / iOS Info.plist GADApplicationIdentifier 와
  // 반드시 일치시켜야 한다(네이티브 매니페스트에도 동일 값 배선됨).
  // 실 AdMob 앱 ID (2026-07-22 발급).
  static const String androidAppId =
      'ca-app-pub-5350763104629231~2588225189';
  static const String iosAppId = 'ca-app-pub-5350763104629231~6895015710';

  // 전면광고 단위.
  // TODO(release): AdMob 콘솔에서 전면광고 단위를 아직 만들지 않았다 — 현재 Google 공개
  //   테스트 단위. 실 앱 ID와 테스트 광고 단위 조합은 허용되나, 출시 전 실 전면광고 단위를
  //   생성해 교체해야 한다(테스트 단위 채로 출시하면 그 게재위치는 수익 0).
  static const String androidInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosInterstitial =
      'ca-app-pub-3940256099942544/4411468910';

  // 리워드 광고 단위(힌트) — 실 AdMob 단위 (2026-07-22 발급).
  static const String androidRewarded =
      'ca-app-pub-5350763104629231/6778751637';
  static const String iosRewarded =
      'ca-app-pub-5350763104629231/7900261619';
}

/// IAP 상품 ID (GDD 12 — 광고 제거 단품).
abstract final class IapProducts {
  /// 광고 제거 비소모성 단품.
  /// TODO(release): App Store Connect / Play Console에 등록한 실제 상품 ID로 교체.
  static const String removeAds = 'remove_ads';

  /// 스토어에 등록해 조회할 상품 ID 집합.
  static const Set<String> all = {removeAds};
}
