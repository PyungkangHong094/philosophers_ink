/// 게임플레이 계층 밸런스 상수. 매직 넘버 금지(GDD 10.5) — 데모 값도 여기 모은다.
///
/// sim의 core/constants.dart(sim-engineer 소유)와 분리한다. 이 파일은 gameplay/
/// 소유. M2부터 실제 값은 레벨 JSON이 대체하고, 여기는 로더 폴백/디버그 기본값만 남는다.
class GameplayConstants {
  GameplayConstants._();

  // --- M1 데모 씬 잉크 예산 (레벨 JSON 대체 전 임시 주입값) ---
  // 단위 = 래스터라이즈 셀 수. 화염/서리는 M1-A 잉크가 붙기 전까지 데모에서 함께 노출해
  // 병 3개·게이지·선택·숨김 UI를 검증한다. 값은 데모 체감용이며 밸런스 근거는 없다.
  /// 데모 석필 예산.
  static const int demoChalkBudget = 1200;

  /// 데모 화염 룬 예산.
  static const int demoHeatBudget = 300;

  /// 데모 서리 룬 예산.
  static const int demoFrostBudget = 300;
}
