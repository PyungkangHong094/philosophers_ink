// 브레젠험 직선 래스터라이즈 (GDD 10.4).
//
// 순수 기하 함수 — 그리드나 물질에 의존하지 않고 셀 좌표 목록만 낸다.
// 스트로크 관리(ID·삭제)는 core/game_state.dart가 이 결과를 소비한다.

/// (x0,y0)–(x1,y1)을 브레젠험으로 래스터라이즈한 1셀 두께 좌표 목록.
/// 각 원소는 [x, y]를 [i], [i+1]로 담는 평면 리스트가 아니라 (x,y) 쌍의 record.
List<(int, int)> bresenham(int x0, int y0, int x1, int y1) {
  final points = <(int, int)>[];
  var x = x0;
  var y = y0;
  final dx = (x1 - x0).abs();
  final dy = (y1 - y0).abs();
  final sx = x0 < x1 ? 1 : -1;
  final sy = y0 < y1 ? 1 : -1;
  var err = dx - dy;

  while (true) {
    points.add((x, y));
    if (x == x1 && y == y1) break;
    final e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x += sx;
    }
    if (e2 < dx) {
      err += dx;
      y += sy;
    }
  }
  return points;
}

/// 두께가 있는 선. 중심선을 브레젠험으로 그린 뒤 각 점을 정사각 브러시로 확장한다.
/// [thickness] 2 → 각 중심점에서 오른쪽·아래로 한 셀씩 더해 2×2 발자국.
///
/// 반환은 중복 제거된 셀 집합(순서는 삽입 순). 잉크 차감은 이 개수로 센다.
List<(int, int)> rasterizeStroke(
  int x0,
  int y0,
  int x1,
  int y1,
  int thickness,
) {
  final seen = <int, bool>{};
  final result = <(int, int)>[];
  // brush 반경: 짝수 두께는 [0, t-1], 즉 중심 기준 오른쪽/아래로 확장.
  for (final (cx, cy) in bresenham(x0, y0, x1, y1)) {
    for (var oy = 0; oy < thickness; oy++) {
      for (var ox = 0; ox < thickness; ox++) {
        final x = cx + ox;
        final y = cy + oy;
        // 좌표를 32비트 키로 인코딩해 중복 제거 (좌표는 그리드 범위 내 소값).
        final key = (x << 16) ^ (y & 0xFFFF);
        if (seen[key] == true) continue;
        seen[key] = true;
        result.add((x, y));
      }
    }
  }
  return result;
}
