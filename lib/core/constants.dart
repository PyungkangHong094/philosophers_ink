/// 모든 밸런스 값의 단일 소스. 게임 로직 내 매직 넘버 금지 (GDD 10.5, 14장).
///
/// M0 스파이크에서 실사용하는 값과, 테이블 구조를 위해 미리 잡아둔 M1 값
/// (전이 확률·dispersion)을 함께 정의한다. M1 값은 주석으로 표시한다.
class SimConstants {
  SimConstants._();

  // --- 그리드 (GDD 10.2) ---
  /// 논리 그리드 가로 셀 수.
  static const int gridWidth = 160;

  /// 논리 그리드 세로 셀 수. 기기 비율에 따라 세로 가변이 원칙이나 M0는 고정.
  static const int gridHeight = 320;

  // --- 틱 (GDD 10.2) ---
  /// 고정 시뮬 틱레이트.
  static const int tickRateHz = 60;

  /// 한 틱의 논리 시간(초). accumulator 기준.
  static const double tickSeconds = 1.0 / tickRateHz;

  /// 프레임 누적 시간 상한(초). 스톨 후 죽음의 나선(spiral of death) 방지.
  static const double maxFrameAccumSeconds = 0.25;

  // --- 결정성 (GDD 10.2) ---
  /// 시드 고정 RNG의 기본 시드. 재시작 동일성의 기준.
  static const int defaultSeed = 0x50494E4B; // "PINK"

  // --- 방출구 (M0 데모 씬) ---
  /// 방출 밴드가 놓이는 행(상단에서부터).
  static const int emitterRow = 2;

  /// 방출 밴드의 중심에서 좌우로 뻗는 셀 수. 총 폭 = 2*half + 1.
  static const int emitterHalfWidth = 6;

  /// 방출 간격(틱). N틱마다 방출 밴드를 채운다. 값이 작을수록 방출 속도가 빠르다.
  static const int emitIntervalTicks = 3;

  // --- 드로잉 입력 (GDD 10.4) ---
  /// 석필 선의 두께(셀). 브레젠험 래스터라이즈 시 이 두께로 확장.
  static const int strokeThicknessCells = 2;

  // --- 상전이 (M1, GDD 4.1·10.2) — 테이블 구조 확보용, M0 미사용 ---
  /// 화염 룬 선의 매 틱 가열 전이 확률.
  static const double pHeat = 0.12; // M1

  /// 서리 룬 선의 매 틱 냉각 전이 확률.
  static const double pCold = 0.12; // M1

  /// 액체 수평 확산 폭(셀). 손맛 튜닝 대상.
  static const int liquidDispersion = 4; // M1
}
