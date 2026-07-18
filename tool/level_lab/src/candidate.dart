/// 스트로크 탐색 솔버의 해 후보 인코딩 (레벨 랩 L1, docs/LEVEL_LAB.md §1).
///
/// 해 후보 = 선분 프리미티브 k개(각: 시작·끝·잉크종류) + 중력 반전 탭 틱 목록.
/// 순수 Dart — flutter 미의존이라 CLI/isolate에서 그대로 돈다.
library;

import 'package:philosophers_ink/sim/materials.dart';

/// 잉크 종류의 JSON 키 (레벨 JSON `ink_budget`과 동일 표기).
String inkKey(InkType t) => switch (t) {
      InkType.chalk => 'chalk',
      InkType.heat => 'heat',
      InkType.frost => 'frost',
    };

InkType? inkFromKey(String k) => switch (k) {
      'chalk' => InkType.chalk,
      'heat' => InkType.heat,
      'frost' => InkType.frost,
      _ => null,
    };

/// 선분 프리미티브 1개: 잉크 종류 + 시작·끝 격자 좌표.
class StrokePrimitive {
  final InkType ink;
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  const StrokePrimitive(this.ink, this.x0, this.y0, this.x1, this.y1);

  StrokePrimitive copyWith({int? x0, int? y0, int? x1, int? y1}) =>
      StrokePrimitive(
        ink,
        x0 ?? this.x0,
        y0 ?? this.y0,
        x1 ?? this.x1,
        y1 ?? this.y1,
      );

  Map<String, dynamic> toJson() => {
        'ink': inkKey(ink),
        'x0': x0,
        'y0': y0,
        'x1': x1,
        'y1': y1,
      };

  static StrokePrimitive fromJson(Map<String, dynamic> m) => StrokePrimitive(
        inkFromKey(m['ink'] as String) ?? InkType.chalk,
        (m['x0'] as num).toInt(),
        (m['y0'] as num).toInt(),
        (m['x1'] as num).toInt(),
        (m['y1'] as num).toInt(),
      );

  @override
  String toString() => '${inkKey(ink)}($x0,$y0)->($x1,$y1)';

  @override
  bool operator ==(Object other) =>
      other is StrokePrimitive &&
      other.ink == ink &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(ink, x0, y0, x1, y1);
}

/// 해 후보: 선분들 + 중력 반전 버튼을 탭할 틱 목록(비어 있으면 탭 없음).
class Candidate {
  final List<StrokePrimitive> strokes;

  /// 이 틱에 도달하기 직전 중력 버튼을 1회 탭한다 (오름차순 권장, 중복 무해).
  final List<int> gravityTaps;

  const Candidate(this.strokes, {this.gravityTaps = const []});

  int get strokeCount => strokes.length;

  Map<String, dynamic> toJson() => {
        'strokes': [for (final s in strokes) s.toJson()],
        'gravity_taps': gravityTaps,
      };

  static Candidate fromJson(Map<String, dynamic> m) => Candidate(
        [
          for (final s in (m['strokes'] as List))
            StrokePrimitive.fromJson((s as Map).cast<String, dynamic>())
        ],
        gravityTaps: [
          for (final t in (m['gravity_taps'] as List? ?? const []))
            (t as num).toInt()
        ],
      );

  @override
  String toString() =>
      'Candidate(${strokes.join(", ")}${gravityTaps.isEmpty ? "" : " taps=$gravityTaps"})';
}
