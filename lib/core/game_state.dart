import '../sim/grid.dart';
import '../sim/materials.dart';
import '../sim/rasterize.dart';
import '../sim/rules.dart';
import 'constants.dart';
import 'rng.dart';

/// 한 스트로크의 기록: 잉크 종류 + 칠한 셀 인덱스 목록 (탭 삭제 단위).
class _Stroke {
  final InkType ink;
  final List<int> cells = <int>[];
  _Stroke(this.ink);
}

/// 시뮬 상태의 소유자 (순수 Dart).
///
/// 그리드 + RNG + 이동/전이 규칙 + 방출구 + 드로잉 스트로크를 묶는다.
/// 렌더링·입력 위젯은 이 클래스의 API만 쓰고, 여기서 flutter를 import하지 않는다.
///
/// 결정성 계약 (GDD 10.5): [reset]이 그리드·RNG 시드·규칙·틱·스트로크를 완전 초기화.
/// 같은 시드 + 같은 입력 시퀀스 → N틱 후 [Grid.hash]가 항상 동일.
class GameState {
  final int seed;
  final Grid grid;
  final DeterministicRng rng;

  /// 방출구가 쏟는 물질 ID. M2 레벨 로더 전까지 데모 파라미터.
  final int emitMaterial;

  /// Rules는 GameState의 rng 인스턴스를 공유한다. reset()이 rng를 초기화하면
  /// 규칙의 무작위성도 함께 되감겨 재시작 결정성이 성립한다.
  late final Rules rules;

  int tickCount = 0;

  final Map<int, _Stroke> _strokes = {};
  int _nextStrokeId = 1;

  GameState({
    this.seed = SimConstants.defaultSeed,
    int? emitMaterial,
  })  : emitMaterial = emitMaterial ?? Material.water.index,
        grid = Grid(SimConstants.gridWidth, SimConstants.gridHeight),
        rng = DeterministicRng(seed) {
    rules = Rules(rng);
  }

  /// 활성 셀 수 — EMPTY도 정적(WALL/룬 선)도 아닌 셀. 디버그 오버레이·오디오(M5)용.
  int get activeCellCount {
    var n = 0;
    final cells = grid.cells;
    for (var i = 0; i < cells.length; i++) {
      if (categoryOf(cells[i]) != MaterialCategory.none &&
          categoryOf(cells[i]) != MaterialCategory.staticSolid) {
        n++;
      }
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

  /// 한 틱: 방출 → 상전이·이동. 순서 고정(결정성).
  void tick() {
    _emit();
    rules.step(grid);
    tickCount++;
  }

  /// 방출구: emitIntervalTicks마다 상단 밴드를 emitMaterial로 채운다 (빈 칸만).
  void _emit() {
    if (tickCount % SimConstants.emitIntervalTicks != 0) return;
    final cx = grid.width ~/ 2;
    final row = SimConstants.emitterRow;
    final half = SimConstants.emitterHalfWidth;
    for (var x = cx - half; x <= cx + half; x++) {
      if (!grid.inBounds(x, row)) continue;
      if (grid.get(x, row) == Material.empty.index) {
        grid.set(x, row, emitMaterial);
      }
    }
  }

  // --- 드로잉 스트로크 API (gameplay-engineer 잉크 예산과의 계약) ---

  /// 스트로크 시작. 잉크 종류를 기록하고 새 스트로크 ID를 반환한다 (아직 칠하지 않음).
  /// 실제 배치·잉크 차감은 [extendStroke]로 한다.
  int beginStroke(InkType ink) {
    final id = _nextStrokeId++;
    _strokes[id] = _Stroke(ink);
    return id;
  }

  /// (x0,y0)–(x1,y1)을 두께 strokeThicknessCells로 래스터라이즈해 잉크 물질을 배치.
  /// **반환값 = 이번에 새로 칠해진 셀 수** (잉크 예산 차감 근거). 이미 무언가 있는
  /// 셀은 덮지 않으므로 반환값이 곧 실제 소모량이다.
  ///
  /// [maxCells]: 이번 호출에서 배치할 EMPTY 셀 수 상한. 잔량보다 많이 칠하는 누수를
  /// 막아 "예산 부족 시 부분 배치 금지"(GDD 4.2)를 세그먼트 단위로 지킨다.
  /// 음수(기본 -1)면 무제한.
  int extendStroke(
    int strokeId,
    int x0,
    int y0,
    int x1,
    int y1, {
    int maxCells = -1,
  }) {
    final stroke = _strokes[strokeId];
    if (stroke == null) return 0;
    if (maxCells == 0) return 0;
    final placed = materialForInk(stroke.ink).index;
    final cells = rasterizeStroke(
      x0,
      y0,
      x1,
      y1,
      SimConstants.strokeThicknessCells,
    );
    var painted = 0;
    for (final (x, y) in cells) {
      if (!grid.inBounds(x, y)) continue;
      if (grid.get(x, y) != Material.empty.index) continue;
      grid.set(x, y, placed);
      stroke.cells.add(grid.index(x, y));
      painted++;
      if (maxCells >= 0 && painted >= maxCells) break; // 예산 상한 도달
    }
    return painted;
  }

  /// 그리드를 바꾸지 않고, 이 세그먼트가 새로 칠할 EMPTY 셀 수를 미리 센다.
  /// all-or-nothing 예산 사전검사용 (GDD 4.2). 직후 [extendStroke]가 같은 좌표로
  /// 칠하면 (그 사이 그리드 변화가 없는 한) 이 값만큼 배치된다.
  int previewStrokeCells(int x0, int y0, int x1, int y1) {
    final cells = rasterizeStroke(
      x0,
      y0,
      x1,
      y1,
      SimConstants.strokeThicknessCells,
    );
    var count = 0;
    for (final (x, y) in cells) {
      if (!grid.inBounds(x, y)) continue;
      if (grid.get(x, y) != Material.empty.index) continue;
      count++;
    }
    return count;
  }

  /// 스트로크가 차지한 셀 수 (예산 조회용).
  int strokeCellCount(int strokeId) => _strokes[strokeId]?.cells.length ?? 0;

  /// 스트로크의 잉크 종류.
  InkType? inkOfStroke(int strokeId) => _strokes[strokeId]?.ink;

  /// ID로 스트로크 삭제. 배치했던 셀이 아직 그 물질이면 EMPTY로 복원.
  /// 삭제된 셀 수 반환(없으면 0). 잉크는 반환하지 않는다 (GDD 4.2).
  int deleteStroke(int strokeId) {
    final stroke = _strokes.remove(strokeId);
    if (stroke == null) return 0;
    final placed = materialForInk(stroke.ink).index;
    var removed = 0;
    for (final cellIndex in stroke.cells) {
      // 배치 물질이 그대로 남아있을 때만 복원 (그 위에 쌓인 입자·전이물 보호).
      if (grid.cells[cellIndex] == placed) {
        grid.cells[cellIndex] = Material.empty.index;
        removed++;
      }
    }
    return removed;
  }

  /// (x, y)를 포함하는 스트로크를 찾아 삭제 (탭 삭제). 성공 시 true.
  bool deleteStrokeAt(int x, int y) {
    if (!grid.inBounds(x, y)) return false;
    final target = grid.index(x, y);
    int? hitId;
    for (final entry in _strokes.entries) {
      if (entry.value.cells.contains(target)) {
        hitId = entry.key;
        break;
      }
    }
    if (hitId == null) return false;
    deleteStroke(hitId);
    return true;
  }
}
