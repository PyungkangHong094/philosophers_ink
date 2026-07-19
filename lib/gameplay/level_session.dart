/// 레벨 한 판의 플레이 세션 — sim(GameState) + 플라스크 판정 + 잉크 예산 + 별점을
/// 묶는 코어 루프 상태 소유자 (GDD 5·10.5). main.dart는 이 세션 API만 쓴다.
///
/// 결정성(GDD 10.5): [tick]은 game.tick() → flasks.update 순서 고정. [reset]이
/// 그리드·RNG·방출 잔량·플라스크·잉크·선택을 전부 초기화하고 지형을 재스탬프한다.
library;

import '../core/constants.dart';
import '../core/game_state.dart';
import '../level/gimmick_builder.dart';
import '../level/level_model.dart';
import '../sim/emitter.dart';
import '../sim/rules.dart' show PhaseChangeCallback;
import 'flask.dart';
import 'gameplay_constants.dart';
import 'ink_budget.dart';
import 'ink_controller.dart';
import 'level_geometry.dart';
import 'star_rating.dart';

/// 중력 반전 토글 1회의 기록 (결정성/리플레이 로그). 몇 번째 틱에 어떤 값으로
/// 토글했는지를 담아, 같은 시드+같은 로그로 재생하면 동일 결과가 나온다 (sim 계약 4절).
class GravityToggle {
  final int tick;
  final bool inverted;
  const GravityToggle(this.tick, this.inverted);
}

/// 레벨 실패 사유 (GDD 2·5.1). shell이 문구를 분기한다.
/// [contamination] 순수 플라스크 ASH 오염, [timeout] 제한 시간 초과.
enum LevelFailure { contamination, timeout }

class LevelSession {
  final Level level;
  final GameState game;
  final FlaskSystem flasks;
  final InkController ink;

  /// 레벨 기믹의 sim 변환 결과 (불변). 중력 반전 버튼 노출 여부도 여기서 읽는다.
  final GimmickBundle gimmicks;

  /// 중력 반전 입력 로그 (결정성 계약). reset()이 비운다.
  final List<GravityToggle> gravityLog = [];

  /// 제한 시간(시뮬 틱). 레벨 `time_limit_s` 또는 난이도 밴드 기본값 × tickRate (GDD 2장).
  final int timeLimitTicks;

  /// 제한 시간 초과 래치 (tick에서 미클리어로 한도 도달 시 true). reset이 되돌린다.
  bool _timedOut = false;

  factory LevelSession(Level level,
      {void Function(SettleEvent event)? onSettle}) {
    final bundle =
        buildGimmicks(level.gimmicks, gridWidth: SimConstants.gridWidth);
    return LevelSession._(level, bundle, onSettle);
  }

  /// 기믹 번들을 미리 만들어 GameState 배선과 [gimmicks] 필드가 같은 인스턴스를 쓰게 한다.
  LevelSession._(
    this.level,
    this.gimmicks,
    void Function(SettleEvent event)? onSettle,
  )   : timeLimitTicks = GameplayConstants.timeLimitTicks(level),
        game = GameState(
          emitters: _mapEmitters(level.emitters),
          gates: gimmicks.gates,
          portals: gimmicks.portals,
          temperatureZones: gimmicks.zones,
        ),
        flasks = FlaskSystem(level.flasks, onSettle: onSettle),
        ink = InkController(_budgetFromLevel(level.inkBudget)) {
    stampLevelGeometry(game.grid, level);
  }

  /// 이 레벨에 중력 반전 버튼 기믹이 있는가 (게임플레이가 버튼 노출 판단).
  bool get hasGravityFlip => gimmicks.hasGravityFlip;

  /// 상전이 관찰 콜백 패스스루 (M5 폴리시). shell이 결빙·증발 SFX를 여기에 배선한다.
  /// (materialFrom, materialTo, x, y). 관찰 전용·결정성 무영향, null이면 비용 0.
  set onPhaseChange(PhaseChangeCallback? cb) => game.onPhaseChange = cb;
  PhaseChangeCallback? get onPhaseChange => game.onPhaseChange;

  /// 현재 중력이 반전(위)되어 있는가.
  bool get gravityInverted => game.gravityInverted;

  /// 중력 반전 버튼 토글 (GDD 6). 기믹이 있는 레벨에서만 동작하며, 실제 변경 시
  /// [gravityLog]에 (틱, 값)을 기록한다 — 결정성 리플레이 계약(sim API 4절).
  void setGravityInverted(bool inverted) {
    if (!hasGravityFlip) return;
    if (game.gravityInverted == inverted) return;
    gravityLog.add(GravityToggle(game.tickCount, inverted));
    game.setGravityInverted(inverted);
  }

  /// 현재 값의 반대로 토글 (버튼 탭 편의).
  void toggleGravity() => setGravityInverted(!game.gravityInverted);

  /// 레벨 방출구 스펙 → sim EmitterConfig.
  static List<EmitterConfig> _mapEmitters(List<EmitterSpec> specs) => [
        for (final e in specs)
          EmitterConfig(
            x: e.x,
            y: e.y,
            width: e.width,
            materialId: e.material.index,
            // rate = 방출 간격(틱). 1 미만은 방어적으로 1로.
            intervalTicks: e.rate.round() < 1 ? 1 : e.rate.round(),
            total: e.total,
            ashRatio: e.ashRatio,
          ),
      ];

  static InkBudget _budgetFromLevel(Map<InkType, int> m) => InkBudget(
        chalk: m[InkType.chalk] ?? 0,
        heat: m[InkType.heat] ?? 0,
        frost: m[InkType.frost] ?? 0,
      );

  /// 한 틱: 시뮬 진행 → 플라스크 판정 (순서 고정, 결정성). 판정 후 제한 시간 초과를
  /// 래치한다 — 미클리어로 한도 틱에 도달하면 timeout 실패. 시간은 시뮬 틱 기반이라
  /// 일시정지(틱 미진행) 중 멈추고 결정성에 무영향이다 (GDD 2장).
  void tick() {
    game.tick();
    flasks.update(game.grid);
    if (!_timedOut && !flasks.isCleared && game.tickCount >= timeLimitTicks) {
      _timedOut = true;
    }
  }

  /// 모든 플라스크 목표 충족 && 순수 오염 없음.
  bool get isCleared => flasks.isCleared;

  /// 실패(재시작 유도) — 순수 오염 또는 제한 시간 초과.
  bool get isFailed => flasks.isFailed || _timedOut;

  /// 제한 시간 초과로 실패했는가.
  bool get isTimedOut => _timedOut;

  /// 실패 사유 (실패가 아니면 null). 오염이 시간 초과보다 우선.
  LevelFailure? get failureReason {
    if (flasks.isFailed) return LevelFailure.contamination;
    if (_timedOut) return LevelFailure.timeout;
    return null;
  }

  /// 남은 시간(시뮬 틱). shell 카운트다운 표시용. 0 미만은 0으로 클램프.
  int get remainingTicks {
    final r = timeLimitTicks - game.tickCount;
    return r < 0 ? 0 : r;
  }

  /// 현재 별점 결과 (사용 잉크 vs 최적해). 미클리어면 0성.
  StarResult get result => computeStars(
        cleared: isCleared,
        inkUsed: ink.budget.totalUsed,
        optimalTotal: level.meta.optimalTotal,
        explicit: level.starThresholds,
      );

  /// 재시작 안전 (GDD 10.5). 3회 연속 동일 동작을 테스트로 보장.
  void reset() {
    game.reset();
    flasks.reset();
    ink.reset();
    gravityLog.clear();
    _timedOut = false;
    stampLevelGeometry(game.grid, level);
  }

  /// 세션이 소유한 notifier를 정리한다. 레벨 화면(play_screen)이 세션을 폐기할 때
  /// 호출한다 — 미호출 시 레벨 재플레이 반복에서 InkController 리스너가 누적된다.
  /// [game]·[flasks]는 notifier가 아니라 별도 정리가 없다. 호출 후 세션은 재사용 불가.
  void dispose() {
    ink.dispose();
  }
}
