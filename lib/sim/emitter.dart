import '../core/constants.dart';

/// 방출구 설정 (GDD 5.2·6·10.6). 순수 Dart.
///
/// [x] 열부터 [width]칸 밴드의 [y] 행에 [intervalTicks]마다 [materialId]를 쏟는다.
/// [total]이 null이면 무한 방출, 그 외면 유한 — 총 [total]셀을 쏟고 멈춘다 (GDD 5.2).
/// [ashRatio]>0이면 방출 셀이 결정성 RNG로 그 확률만큼 ASH로 치환된다 (재 방출구, GDD 6).
///
/// 레벨 로더(M2-C, gameplay)가 레벨 JSON을 이 타입으로 매핑해 GameState에 주입한다.
class EmitterConfig {
  final int x;
  final int y;
  final int width;
  final int materialId;
  final int intervalTicks;

  /// 총 방출 셀 수. null이면 무한.
  final int? total;

  /// 0~1: 방출 셀이 ASH로 치환될 확률. 0이면 RNG를 소비하지 않는다.
  final double ashRatio;

  /// 남은 방출 셀 수(런타임). reset이 [total]로 되돌린다. 무한이면 null.
  int? remaining;

  EmitterConfig({
    required this.x,
    required this.y,
    required this.materialId,
    this.width = 1,
    this.intervalTicks = SimConstants.emitIntervalTicks,
    this.total,
    this.ashRatio = 0.0,
  }) : remaining = total;

  bool get isInfinite => total == null;

  bool get exhausted => remaining != null && remaining! <= 0;

  /// 재시작 시 런타임 잔량 복원 (결정성).
  void resetRuntime() {
    remaining = total;
  }
}
