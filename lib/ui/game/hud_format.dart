/// HUD 수치 포매팅 (순수 로직, 단위 테스트 대상).
///
/// 초시계는 **시뮬 틱 기반**(벽시계 아님) — tickCount ÷ 60(tickRateHz). 시뮬은 재생 중에만
/// 틱하므로 일시정지·백그라운드에서 자동 정지하고, reset()이 tickCount를 0으로 되돌린다.
library;

import '../../core/constants.dart';

/// 시뮬 틱 수 → "MM:SS" 경과 시간. 분은 최소 2자리, 60분 이상도 그대로 누적.
String formatElapsed(int ticks) => formatClock(ticks ~/ SimConstants.tickRateHz);

/// 초 → "MM:SS" 시계 문자열 (카운트다운 HUD·경과 시간 공용). 음수는 0으로 클램프.
String formatClock(int totalSeconds) {
  final t = totalSeconds < 0 ? 0 : totalSeconds;
  final m = t ~/ 60;
  final s = t % 60;
  return '${_pad2(m)}:${_pad2(s)}';
}

String _pad2(int v) => v < 10 ? '0$v' : '$v';
