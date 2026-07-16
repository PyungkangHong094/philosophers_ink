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

  // --- 상전이·확산 (M1, GDD 3.3·4.1·10.2) ---
  // 아래 값들은 전부 체감 튜닝 대상(오픈 이슈 #1·#2). 밸런스는 여기서만 바꾼다.

  /// 화염 룬 선(HEAT_LINE)이 인접 4방향 셀을 매 틱 +1단계 가열할 확률 (오픈 이슈 #1).
  static const double pHeat = 0.12;

  /// 서리 룬 선(COLD_LINE)이 인접 4방향 셀을 매 틱 −1단계 냉각할 확률 (오픈 이슈 #1).
  static const double pCold = 0.12;

  /// 액체(WATER/LAVA) 한 틱 수평 확산 최대 셀 수. 클수록 잘 퍼진다(손맛의 절반, GDD 13장).
  static const int liquidDispersion = 4;

  /// 기체(STEAM) 한 틱 수평 확산 최대 셀 수. 액체보다 조금 덜 퍼지게.
  static const int gasDispersion = 3;

  /// 얼음(ICE) 안식각 노브 (오픈 이슈 #2). 낙하가 막힌 얼음이 매 틱 이 확률로 옆으로
  /// 한 칸 미끄러진다. 높을수록 더미가 평평해진다(안식각↓, "미끄러워 잘 퍼짐" GDD 3.1).
  static const double iceSlipChance = 0.45;

  // --- M0 데모 방출구 물질 override는 GameState 생성자 파라미터로 (레벨은 M2) ---
}
