import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/sim/rasterize.dart';

void main() {
  group('bresenham', () {
    test('수평선은 끝점 포함 연속 셀', () {
      expect(bresenham(0, 0, 3, 0), [(0, 0), (1, 0), (2, 0), (3, 0)]);
    });

    test('45도 대각선', () {
      expect(bresenham(0, 0, 2, 2), [(0, 0), (1, 1), (2, 2)]);
    });

    test('역방향도 양 끝점 포함, 길이 동일', () {
      final p = bresenham(3, 1, 0, 1);
      expect(p.first, (3, 1));
      expect(p.last, (0, 1));
      expect(p.length, 4);
    });

    test('수직선', () {
      expect(bresenham(4, 0, 4, 2), [(4, 0), (4, 1), (4, 2)]);
    });

    test('완만한 기울기 (dx > dy)', () {
      // (0,0)→(4,2): x가 지배, 각 x마다 y가 서서히 증가.
      final p = bresenham(0, 0, 4, 2);
      expect(p.first, (0, 0));
      expect(p.last, (4, 2));
      // x는 0..4 모두 최소 한 번 등장.
      final xs = p.map((c) => c.$1).toSet();
      expect(xs, {0, 1, 2, 3, 4});
    });
  });

  group('rasterizeStroke (두께 2)', () {
    test('단일 점은 2×2 발자국', () {
      final cells = rasterizeStroke(5, 5, 5, 5, 2);
      expect(cells.toSet(), {(5, 5), (6, 5), (5, 6), (6, 6)});
    });

    test('겹치는 브러시 셀은 중복 제거된다', () {
      final cells = rasterizeStroke(0, 0, 3, 0, 2);
      expect(cells.length, cells.toSet().length, reason: '중복 없음');
      // 두께 2 수평선: 두 행(y=0,1) × x=0..4(중심 0..3 + 브러시 확장 1).
      expect(cells.toSet(), containsAll([(0, 0), (0, 1), (3, 0), (4, 1)]));
    });

    test('두께 1은 브레젠험 셀 그대로', () {
      final cells = rasterizeStroke(0, 0, 3, 0, 1);
      expect(cells, [(0, 0), (1, 0), (2, 0), (3, 0)]);
    });
  });
}
