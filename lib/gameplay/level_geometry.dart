/// 레벨의 정적 지형 + 플라스크 비커 벽을 그리드에 스탬프한다 (GDD 5.1 입구 규칙). 순수 Dart.
///
/// [LevelSession]과 [HeadlessSession](솔버)이 **공용**한다 — 솔버가 실게임과 정확히 같은
/// 벽 물리를 보도록 단일 소스로 둔다(두 세션이 어긋나면 솔버 결과가 게임과 달라진다).
///
/// 좌표: 셀 (x,y), row-major. 벽은 [Material.wall].
library;

import '../level/level_model.dart';
import '../sim/grid.dart';

/// 지형 먼저, 비커 벽을 나중에 찍어 겹칠 때 비커 무결성이 이긴다.
void stampLevelGeometry(Grid grid, Level level) {
  _stampTerrain(grid, level);
  _stampFlaskWalls(grid, level);
}

void _stampTerrain(Grid grid, Level level) {
  for (final t in level.terrain) {
    for (var yy = t.y; yy < t.y + t.h; yy++) {
      for (var xx = t.x; xx < t.x + t.w; xx++) {
        if (grid.inBounds(xx, yy)) grid.set(xx, yy, t.material.index);
      }
    }
  }
}

/// 각 플라스크를 개방형 비커로 만든다: 벽 3면을 WALL로 세우고 개방부([FlaskMouth])만 연다.
/// 좌·우 벽은 방향 무관 전체 높이, 개방부 반대편 가로 변(mouth up→바닥, down→윗변)에 뚜껑.
/// 벽 셀(staticSolid)은 판정에서 제외되므로 카운트 영역은 자연히 내부로 좁혀진다.
void _stampFlaskWalls(Grid grid, Level level) {
  final wall = Material.wall.index;
  for (final f in level.flasks) {
    final left = f.x;
    final right = f.x + f.w - 1;
    final top = f.y;
    final bottom = f.y + f.h - 1;
    // 좌·우 벽 (전체 높이, 방향 무관).
    for (var yy = top; yy <= bottom; yy++) {
      if (grid.inBounds(left, yy)) grid.set(left, yy, wall);
      if (grid.inBounds(right, yy)) grid.set(right, yy, wall);
    }
    // 개방부 반대편 뚜껑 벽: mouth up → 바닥, mouth down → 윗변.
    final capRow = f.mouth == FlaskMouth.down ? top : bottom;
    for (var xx = left; xx <= right; xx++) {
      if (grid.inBounds(xx, capRow)) grid.set(xx, capRow, wall);
    }
  }
}
