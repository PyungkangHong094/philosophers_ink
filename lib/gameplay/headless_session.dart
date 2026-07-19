/// 오프라인(헤드리스) 레벨 세션 — 레벨 랩 솔버(tool/level_lab)가 대량 롤아웃에 쓴다.
///
/// [LevelSession]과 판정·틱·재시작 계약이 동일하되, **flutter 미의존**이라는 점만 다르다.
/// LevelSession은 [InkController](ChangeNotifier)를 소유해 `package:flutter/foundation`을
/// 끌어오므로 순수 `dart run` CLI에서 컴파일되지 않는다. 이 세션은 UI 통지가 필요 없는
/// 오프라인 탐색용이라 잉크 회계를 [InkBudget]으로 직접 하고 flutter를 전혀 import하지 않는다.
///
/// 게임 동작 충실도(솔버가 실제 게임과 같은 판정을 보도록): 기믹 조립([buildGimmicks]),
/// 방출구 매핑, 틱 순서(game.tick → flasks.update), 지형 스탬프, 부분 배치 cap 청구 모델을
/// 전부 LevelSession과 동일한 순서·규칙으로 수행한다. sim은 공개 API로만 소비한다.
///
/// 결정성(GDD 10.5): 같은 시드 + 같은 스트로크·중력 입력 시퀀스 → 동일 결과.
library;

import '../core/constants.dart';
import '../core/game_state.dart';
import '../level/gimmick_builder.dart';
import '../level/level_model.dart';
import '../sim/emitter.dart';
import 'flask.dart';
import 'gameplay_constants.dart';
import 'ink_budget.dart';
import 'level_geometry.dart';

/// 헤드리스 한 판. 소유: sim [GameState] + [FlaskSystem] 판정 + [InkBudget] 회계.
class HeadlessSession {
  final Level level;
  final GameState game;
  final FlaskSystem flasks;
  final InkBudget ink;
  final GimmickBundle gimmicks;

  /// 제한 시간(시뮬 틱). LevelSession과 동일 규칙 — 솔버가 실게임 한도를 그대로 본다.
  final int timeLimitTicks;

  /// 제한 시간 초과 래치. reset이 되돌린다.
  bool _timedOut = false;

  factory HeadlessSession(Level level) {
    final bundle =
        buildGimmicks(level.gimmicks, gridWidth: SimConstants.gridWidth);
    return HeadlessSession._(level, bundle);
  }

  HeadlessSession._(this.level, this.gimmicks)
      : timeLimitTicks = GameplayConstants.timeLimitTicks(level),
        game = GameState(
          emitters: _mapEmitters(level.emitters),
          gates: gimmicks.gates,
          portals: gimmicks.portals,
          temperatureZones: gimmicks.zones,
        ),
        flasks = FlaskSystem(level.flasks),
        ink = InkBudget(
          chalk: level.inkBudget[InkType.chalk] ?? 0,
          heat: level.inkBudget[InkType.heat] ?? 0,
          frost: level.inkBudget[InkType.frost] ?? 0,
        ) {
    stampLevelGeometry(game.grid, level);
  }

  /// 이 레벨에 중력 반전 버튼 기믹이 있는가.
  bool get hasGravityFlip => gimmicks.hasGravityFlip;

  /// 현재 중력이 반전(위)되어 있는가.
  bool get gravityInverted => game.gravityInverted;

  /// UI에 노출되는(예산>0) 잉크 종류 — 솔버가 이 종류만 후보로 삼는다.
  List<InkType> get visibleInks => ink.visibleInks;

  /// 소비한 잉크 총량 (별점·min_ink의 근거).
  int get inkUsed => ink.totalUsed;

  /// 모든 플라스크 목표 충족 && 순수 오염 없음.
  bool get isCleared => flasks.isCleared;

  /// 실패 — 순수 오염 또는 제한 시간 초과 (LevelSession과 동일 계약).
  bool get isFailed => flasks.isFailed || _timedOut;

  /// 제한 시간 초과로 실패했는가.
  bool get isTimedOut => _timedOut;

  /// 남은 시간(시뮬 틱). 0 미만은 0으로 클램프.
  int get remainingTicks {
    final r = timeLimitTicks - game.tickCount;
    return r < 0 ? 0 : r;
  }

  /// 플라스크별 현재 카운트 합 (진행 정체 조기 종료 판정용).
  int get flaskProgress {
    var n = 0;
    for (final f in flasks.flasks) {
      n += f.count;
    }
    return n;
  }

  /// 중력 반전 버튼 토글 (있는 레벨에서만). LevelSession과 동일 계약.
  void setGravityInverted(bool inverted) {
    if (!hasGravityFlip) return;
    if (game.gravityInverted == inverted) return;
    game.setGravityInverted(inverted);
  }

  /// 현재 값의 반대로 토글 (버튼 탭 1회).
  void toggleGravity() => setGravityInverted(!game.gravityInverted);

  /// 스트로크 프리미티브 1개 배치 — 부분 배치 cap 청구 모델(GDD 4.2)을 그대로 따른다.
  /// 잔량 한도 내에서 (x0,y0)–(x1,y1)을 래스터라이즈해 배치하고 **실제 배치 셀 수**만큼
  /// 예산을 차감한다. 숨김/고갈 잉크는 0을 반환한다. 반환값 = 배치·차감된 셀 수.
  int applyStroke(InkType inkType, int x0, int y0, int x1, int y1) {
    if (ink.isHidden(inkType)) return 0;
    final rem = ink.remaining(inkType);
    if (rem <= 0) return 0;
    final id = game.beginStroke(inkType);
    final placed = game.extendStroke(id, x0, y0, x1, y1, maxCells: rem);
    ink.chargeAvailable(inkType, placed);
    return placed;
  }

  /// 한 틱: 시뮬 진행 → 플라스크 판정 (순서 고정, 결정성). 제한 시간 초과도 래치한다
  /// (LevelSession.tick과 동일 계약).
  void tick() {
    game.tick();
    flasks.update(game.grid);
    if (!_timedOut && !flasks.isCleared && game.tickCount >= timeLimitTicks) {
      _timedOut = true;
    }
  }

  /// 재시작 안전 (GDD 10.5). 그리드·RNG·방출 잔량·플라스크·잉크·중력·시간을 초기화하고
  /// 지형·비커 벽을 재스탬프한다. game.reset()이 중력을 기본(아래)으로 되돌린다.
  void reset() {
    game.reset();
    flasks.reset();
    ink.reset();
    _timedOut = false;
    stampLevelGeometry(game.grid, level);
  }

  /// 레벨 방출구 스펙 → sim EmitterConfig (LevelSession._mapEmitters와 동일 규칙).
  static List<EmitterConfig> _mapEmitters(List<EmitterSpec> specs) => [
        for (final e in specs)
          EmitterConfig(
            x: e.x,
            y: e.y,
            width: e.width,
            materialId: e.material.index,
            intervalTicks: e.rate.round() < 1 ? 1 : e.rate.round(),
            total: e.total,
            ashRatio: e.ashRatio,
          ),
      ];
}
