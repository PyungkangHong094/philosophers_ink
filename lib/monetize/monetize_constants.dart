/// 수익화 상수 (GDD 12장) — 앱/광고 단위 ID·IAP 상품 ID의 단일 소스.
///
/// 위젯·서비스 코드에 매직 넘버·문자열 ID 직접 기입 금지 — 전부 여기서 참조한다.
///
/// 수익화 모델 (2026-07-22 개편 — 사용자 디렉션): **전면광고 폐지, 보상형 광고만**.
/// 유일한 광고는 opt-in 리워드(힌트 시청)뿐이고, 강제 광고는 없다. IAP는 그 리워드
/// 시청조차 면제하는 "힌트 광고 없이 보기" 단품이다.
library;

/// AdMob 앱/광고 단위 ID.
///
/// 테스트 ID 출처: https://developers.google.com/admob/{android,ios}/test-ads
abstract final class AdUnits {
  // 앱 ID — AndroidManifest meta-data / iOS Info.plist GADApplicationIdentifier 와
  // 반드시 일치시켜야 한다(네이티브 매니페스트에도 동일 값 배선됨).
  // 실 AdMob 앱 ID (2026-07-22 발급).
  static const String androidAppId =
      'ca-app-pub-5350763104629231~2588225189';
  static const String iosAppId = 'ca-app-pub-5350763104629231~6895015710';

  // 리워드 광고 단위(힌트) — 실 AdMob 단위 (2026-07-22 발급). 앱의 유일한 광고.
  static const String androidRewarded =
      'ca-app-pub-5350763104629231/6778751637';
  static const String iosRewarded =
      'ca-app-pub-5350763104629231/7900261619';
}

/// IAP 상품 ID (GDD 12 — 힌트 광고 면제 단품).
abstract final class IapProducts {
  /// "힌트를 광고 없이 보기" 비소모성 단품. 구매 시 힌트가 리워드 광고 시청 없이
  /// 즉시 열린다(전면광고 폐지 후 유일한 유료 항목).
  /// TODO(release): App Store Connect / Play Console에 등록한 실제 상품 ID로 교체.
  static const String adFreeHints = 'ad_free_hints';

  /// 스토어에 등록해 조회할 상품 ID 집합.
  static const Set<String> all = {adFreeHints};
}
