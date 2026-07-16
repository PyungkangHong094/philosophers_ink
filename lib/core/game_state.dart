import '../sim/grid.dart';
import '../sim/materials.dart';
import '../sim/rasterize.dart';
import '../sim/rules.dart';
import 'constants.dart';
import 'rng.dart';

/// M0 시뮬 상태의 소유자 (순수 Dart).
///
/// 그리드 + RNG + 이동 규칙 + 방출구 + 드로잉 스트로크를 묶는다.
/// 렌더링·입력 위젯은 이 클래스의 API만 쓰고, 여기서 flutter를 import하지 않는다.
///
/// 결정성 계약 (GDD 10.5): [reset]이 그리드·RNG 시드·규칙·틱·스트로크를 완전 초기화.
/// 같은 시드 + 같은 입력 시퀀스 → N틱 후 [Grid.hash]가 항상 동일.
class GameState {
  final int seed;
  final Grid grid;
  final DeterministicRng rng;

  /// Rules는 GameState의 rng 인스턴스를 공유한다. reset()이 rng를 초기화하면
  /// 규칙의 무작위성도 함께 되감겨 재시작 결정성이 성립한다.
  late final Rules rules;

  int tickCount = 0;

  /// 스트로크 ID → 그 스트로크가 칠한 셀 인덱스 목록 (탭 삭제 단위).
  final Map<int, List<int>> _strokes = {};
  int _nextStrokeId = 1;

  GameState({this.seed = SimConstants.defaultSeed})
      : grid = Grid(SimConstants.gridWidth, SimConstants.gridHeight),
        rng = DeterministicRng(seed) {
    rules = Rules(rng);
  }

  /// 활성 입자 수 — EMPTY도 WALL도 아닌 셀. 디버그 오버레이·오디오(M5)용.
  int get activeCellCount {
    var n = 0;
    final cells = grid.cells;
    for (var i = 0; i < cells.length; i++) {
      final id = cells[i];
      if (id != Material.empty.index && id != Material.wall.index) n++;
    }
    return n;
  }

  /// 재시작 안전 (GDD 10.5). 3회 연속 호출 시 동일 동작을 테스트로 보장.
  void reset() {
    grid.clear();
    rng.reset(seed);
    rules.reset();
    tickCount = 0;
    _strokes.clear();
    _nextStrokeId = 1;
  }

  /// 한 틱: 방출 → 이동. 순서 고정(결정성).
  void tick() {
    _emit();
    rules.step(grid);
    tickCount++;
  }

  /// 방출구: emitIntervalTicks마다 상단 밴드를 PRIMA로 채운다 (빈 칸만).
  void _emit() {
    if (tickCount % SimConstants.emitIntervalTicks != 0) return;
    final cx = grid.width ~/ 2;
    final row = SimConstants.emitterRow;
    final half = SimConstants.emitterHalfWidth;
    for (var x = cx - half; x <= cx + half; x++) {
      if (!grid.inBounds(x, row)) continue;
      if (grid.get(x, row) == Material.empty.index) {
        grid.set(x, row, Material.prima.index);
      }
    }
  }

  /// 스트로크 시작 → 첫 세그먼트를 그리고 새 스트로크 ID 반환.
  int beginStroke(int x, int y) {
    final id = _nextStrokeId++;
    _strokes[id] = <int>[];
    _paintSegment(id, x, y, x, y);
    return id;
  }

  /// 이어진 세그먼트를 스트로크에 추가.
  void extendStroke(int strokeId, int x0, int y0, int x1, int y1) {
    _paintSegment(strokeId, x0, y0, x1, y1);
  }

  /// (x0,y0)–(x1,y1)을 두께 strokeThicknessCells의 WALL로 래스터라이즈.
  /// 이미 무언가 있는 셀은 덮지 않는다(잉크 차감/복원 회계의 정확성).
  void _paintSegment(int strokeId, int x0, int y0, int x1, int y1) {
    final owned = _strokes[strokeId];
    if (owned == null) return;
    final cells = rasterizeStroke(
      x0,
      y0,
      x1,
      y1,
      SimConstants.strokeThicknessCells,
    );
    for (final (x, y) in cells) {
      if (!grid.inBounds(x, y)) continue;
      if (grid.get(x, y) != Material.empty.index) continue;
      grid.set(x, y, Material.wall.index);
      owned.add(grid.index(x, y));
    }
  }

  /// (x, y)를 포함하는 스트로크를 찾아 삭제. 해당 셀을 EMPTY로 복원.
  /// 삭제 성공 시 true. 잉크는 반환하지 않는다 (M1 회계 — 지금은 무제한).
  bool deleteStrokeAt(int x, int y) {
    if (!grid.inBounds(x, y)) return false;
    final target = grid.index(x, y);
    int? hitId;
    for (final entry in _strokes.entries) {
      if (entry.value.contains(target)) {
        hitId = entry.key;
        break;
      }
    }
    if (hitId == null) return false;
    for (final cellIndex in _strokes[hitId]!) {
      // 스트로크가 칠한 셀이 아직 WALL일 때만 복원 (그 위에 쌓인 입자 보호).
      if (grid.cells[cellIndex] == Material.wall.index) {
        grid.cells[cellIndex] = Material.empty.index;
      }
    }
    _strokes.remove(hitId);
    return true;
  }
}
