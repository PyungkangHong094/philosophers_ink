import 'constants.dart';

/// 60Hz 고정 틱 + accumulator (GDD 10.2). 렌더 프레임과 시뮬 틱을 분리한다.
///
/// 순수 Dart로 유지하기 위해 Ticker 자체는 소유하지 않는다. 위젯이 Ticker를
/// 만들고 매 vsync 프레임마다 [advance]에 경과 시간을 넘긴다. 이렇게 하면
/// 루프 로직을 flutter 없이 단위 테스트할 수 있다.
class GameLoop {
  /// 고정 틱마다 호출. 보통 GameState.tick.
  final void Function() onTick;

  double _accumulator = 0;
  Duration _last = Duration.zero;
  bool _started = false;

  /// 마지막 프레임에서 실행된 틱 수 (디버그 오버레이용).
  int lastTicksThisFrame = 0;

  GameLoop({required this.onTick});

  /// 재시작 시 누적기·시간 기준을 초기화.
  void reset() {
    _accumulator = 0;
    _last = Duration.zero;
    _started = false;
    lastTicksThisFrame = 0;
  }

  /// vsync 프레임 콜백. [elapsed]는 Ticker가 주는 누적 경과 시간.
  /// 누적된 시간만큼 고정 틱을 몰아서 실행하고 실행 횟수를 반환한다.
  int advance(Duration elapsed) {
    if (!_started) {
      // 첫 프레임: 기준 시각만 잡고 틱은 돌리지 않는다 (거대한 dt 방지).
      _last = elapsed;
      _started = true;
      lastTicksThisFrame = 0;
      return 0;
    }
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt < 0) dt = 0;
    _accumulator += dt;
    if (_accumulator > SimConstants.maxFrameAccumSeconds) {
      _accumulator = SimConstants.maxFrameAccumSeconds;
    }
    var n = 0;
    while (_accumulator >= SimConstants.tickSeconds) {
      onTick();
      _accumulator -= SimConstants.tickSeconds;
      n++;
    }
    lastTicksThisFrame = n;
    return n;
  }
}
