/// 게임플레이 계층 밸런스 상수. 매직 넘버 금지(GDD 10.5) — 데모 값도 여기 모은다.
///
/// sim의 core/constants.dart(sim-engineer 소유)와 분리한다. 이 파일은 gameplay/
/// 소유. M2부터 실제 값은 레벨 JSON이 대체하고, 여기는 로더 폴백/디버그 기본값만 남는다.
///
/// 순수 Dart(flutter 미의존) — 헤드리스 솔버(HeadlessSession)도 이 상수를 공유한다.
library;

import '../core/constants.dart';
import '../level/level_model.dart';

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

  // --- 제한 시간 (GDD 2장 / LEVELS §2.2) ---
  /// D밴드별 기본 제한 시간(초) = D밴드 목표 소요 상한 × 2.
  /// D1–2 80 · D3–4 180 · D5–6 360 · D7–8 720 · D9–10 1,440.
  /// 레벨 JSON `time_limit_s`가 있으면 그 값이 우선한다.
  static int defaultTimeLimitSeconds(int difficulty) {
    if (difficulty <= 2) return 80;
    if (difficulty <= 4) return 180;
    if (difficulty <= 6) return 360;
    if (difficulty <= 8) return 720;
    return 1440;
  }

  /// 레벨의 제한 시간 → 시뮬 틱. `time_limit_s` 우선, 없으면 난이도 밴드 기본값 × tickRate.
  /// LevelSession·HeadlessSession 공유 — 게임·솔버가 같은 한도를 본다.
  static int timeLimitTicks(Level level) {
    final seconds = level.timeLimitSeconds ??
        defaultTimeLimitSeconds(level.meta.difficulty);
    return seconds * SimConstants.tickRateHz;
  }
}
