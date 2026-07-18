/// 초경량 인자 파서 (레벨 랩 CLI). `--key value`와 `--flag` 형태만 다룬다.
/// 외부 args 패키지 의존을 피해 순수 Dart로 둔다.
library;

class CliArgs {
  final Map<String, String> _values = {};
  final Set<String> _flags = {};

  CliArgs(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (!a.startsWith('--')) continue;
      final key = a.substring(2);
      final next = i + 1 < argv.length ? argv[i + 1] : null;
      if (next == null || next.startsWith('--')) {
        _flags.add(key);
      } else {
        _values[key] = next;
        i++;
      }
    }
  }

  bool has(String key) => _flags.contains(key) || _values.containsKey(key);
  String? str(String key) => _values[key];
  int intOr(String key, int fallback) =>
      _values[key] == null ? fallback : int.parse(_values[key]!);
}
