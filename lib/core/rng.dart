/// 시드 고정 결정성 RNG (GDD 10.2).
///
/// 게임 내 모든 무작위성은 이 클래스의 단일 인스턴스에서만 나온다.
/// `dart:math`의 Random()을 새로 만들거나 DateTime.now()에 의존하는 로직은 금지.
///
/// 구현은 xorshift32 — 플랫폼·SDK 구현 세부에 의존하지 않는 순수 정수 연산이라
/// 재시작·리플레이·힌트 검증에서 완전한 재현성을 보장한다.
class DeterministicRng {
  int _state;

  DeterministicRng(int seed) : _state = _sanitize(seed);

  /// 시드를 갈아끼워 상태를 완전 초기화. GameState.reset()에서 호출.
  void reset(int seed) {
    _state = _sanitize(seed);
  }

  /// 0이 되면 xorshift가 0에 갇히므로 1로 대체하고 32비트로 마스킹.
  static int _sanitize(int seed) {
    final s = seed & 0xFFFFFFFF;
    return s == 0 ? 1 : s;
  }

  /// 다음 32비트 부호 없는 난수.
  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// 균등 분포 bool. 입자 대각 이동의 좌우 선택 등에 사용.
  bool nextBool() => (nextUint32() & 1) == 1;

  /// [0.0, 1.0) 범위 double. 확률 전이(M1)에 사용.
  double nextDouble() => nextUint32() / 4294967296.0; // 2^32

  /// [0, max) 범위 정수. max > 0 이어야 한다.
  int nextInt(int max) => nextUint32() % max;
}
