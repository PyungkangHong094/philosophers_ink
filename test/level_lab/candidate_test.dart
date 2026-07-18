import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/sim/materials.dart';

import '../../tool/level_lab/src/candidate.dart';

void main() {
  group('프리미티브 인코딩', () {
    test('inkKey/inkFromKey 왕복', () {
      for (final t in InkType.values) {
        expect(inkFromKey(inkKey(t)), t);
      }
      expect(inkFromKey('nope'), isNull);
    });

    test('StrokePrimitive JSON 왕복', () {
      const s = StrokePrimitive(InkType.frost, 3, 5, 40, 120);
      final back = StrokePrimitive.fromJson(s.toJson());
      expect(back, s);
      expect(back.ink, InkType.frost);
      expect(back.x0, 3);
      expect(back.y1, 120);
    });

    test('Candidate JSON 왕복 (스트로크 + 중력 탭)', () {
      const c = Candidate([
        StrokePrimitive(InkType.chalk, 10, 20, 30, 40),
        StrokePrimitive(InkType.heat, 1, 2, 3, 4),
      ], gravityTaps: [0, 120]);
      final back = Candidate.fromJson(c.toJson());
      expect(back.strokes.length, 2);
      expect(back.strokes[0], c.strokes[0]);
      expect(back.strokes[1], c.strokes[1]);
      expect(back.gravityTaps, [0, 120]);
    });

    test('빈 후보 왕복', () {
      const c = Candidate([]);
      final back = Candidate.fromJson(c.toJson());
      expect(back.strokes, isEmpty);
      expect(back.gravityTaps, isEmpty);
    });

    test('StrokePrimitive 동등성/해시', () {
      const a = StrokePrimitive(InkType.chalk, 1, 1, 2, 2);
      const b = StrokePrimitive(InkType.chalk, 1, 1, 2, 2);
      const c = StrokePrimitive(InkType.heat, 1, 1, 2, 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
