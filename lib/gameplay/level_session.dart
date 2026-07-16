/// 레벨 한 판의 플레이 세션 — sim(GameState) + 플라스크 판정 + 잉크 예산 + 별점을
/// 묶는 코어 루프 상태 소유자 (GDD 5·10.5). main.dart는 이 세션 API만 쓴다.
///
/// 결정성(GDD 10.5): [tick]은 game.tick() → flasks.update 순서 고정. [reset]이
/// 그리드·RNG·방출 잔량·플라스크·잉크·선택을 전부 초기화하고 지형을 재스탬프한다.
library;

import '../core/game_state.dart';
import '../level/level_model.dart';
import '../sim/emitter.dart';
import 'flask.dart';
import 'ink_budget.dart';
import 'ink_controller.dart';
import 'star_rating.dart';

class LevelSession {
  final Level level;
  final GameState game;
  final FlaskSystem flasks;
  final InkController ink;

  LevelSession(this.level, {void Function(SettleEvent event)? onSettle})
      : game = GameState(emitters: _mapEmitters(level.emitters)),
        flasks = FlaskSystem(level.flasks, onSettle: onSettle),
        ink = InkController(_budgetFromLevel(level.inkBudget)) {
    _stampTerrain();
  }

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

  /// 정적 지형을 그리드에 스탬프. 방출·이동은 이 셀들을 피한다(벽).
  void _stampTerrain() {
    for (final t in level.terrain) {
      for (var yy = t.y; yy < t.y + t.h; yy++) {
        for (var xx = t.x; xx < t.x + t.w; xx++) {
          if (game.grid.inBounds(xx, yy)) {
            game.grid.set(xx, yy, t.material.index);
          }
        }
      }
    }
  }

  /// 한 틱: 시뮬 진행 → 플라스크 판정 (순서 고정, 결정성).
  void tick() {
    game.tick();
    flasks.update(game.grid);
  }

  /// 모든 플라스크 목표 충족 && 순수 오염 없음.
  bool get isCleared => flasks.isCleared;

  /// 순수 오염 → 실패 (재시작 유도).
  bool get isFailed => flasks.isFailed;

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
    _stampTerrain();
  }
}
