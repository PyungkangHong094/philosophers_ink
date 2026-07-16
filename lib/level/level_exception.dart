/// 레벨 로딩·검증 실패는 조용히 스킵하지 않고 이 예외로 명시화한다 (GDD 10.6 계약).
library;

/// 레벨 JSON의 구조적/의미적 오류. [problems]에 모든 위반을 모아 던진다.
class LevelException implements Exception {
  /// 어떤 레벨을 로드하다 실패했는지 (파일명·id 등). 없으면 'level'.
  final String source;

  /// 사람이 읽는 위반 목록. 하나 이상.
  final List<String> problems;

  LevelException(this.problems, {this.source = 'level'})
      : assert(problems.isNotEmpty, 'LevelException은 최소 1개 문제를 담아야 한다');

  /// 단일 메시지 편의 생성자.
  LevelException.single(String problem, {String source = 'level'})
      : this([problem], source: source);

  @override
  String toString() {
    final buf = StringBuffer('LevelException($source): ${problems.length}개 문제');
    for (final p in problems) {
      buf.write('\n  - $p');
    }
    return buf.toString();
  }
}
