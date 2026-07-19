import '../sim/emitter.dart';
import '../sim/gimmicks.dart';
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

  /// 방출구 목록 (GDD 5.2·10.6). 다중·유한·물질별·재혼합. reset이 각 잔량을 복원.
  /// 레벨 로더(M2-C)가 JSON에서 이 리스트를 구성한다.
  final List<EmitterConfig> emitters;

  /// 변성 게이트 목록 (GDD 6). 레벨 데이터(불변). 매 틱 이동 전에 존의 물질을 변환한다.
  final List<TransmutationGate> gates;

  /// 포탈 목록 (GDD 6). 레벨 데이터(불변). 매 틱 이동 후 입구→출구 텔레포트.
  final List<Portal> portals;

  /// 온도 존 목록 (GDD 6). 레벨 데이터(불변). 매 틱 존 셀을 가열/냉각(룬 없는 상전이).
  final List<TemperatureZone> temperatureZones;

  /// Rules는 GameState의 rng 인스턴스를 공유한다. reset()이 rng를 초기화하면
  /// 규칙의 무작위성도 함께 되감겨 재시작 결정성이 성립한다.
  late final Rules rules;

  int tickCount = 0;

  final Map<int, _Stroke> _strokes = {};
  int _nextStrokeId = 1;

  /// [emitters]를 주면 그 목록을, 없으면 [emitMaterial](기본 WATER)로 상단 중앙
  /// 단일 무한 방출구를 만든다(데모·M0/M1 호환).
  GameState({
    this.seed = SimConstants.defaultSeed,
    int? emitMaterial,
    List<EmitterConfig>? emitters,
    List<TransmutationGate>? gates,
    List<Portal>? portals,
    List<TemperatureZone>? temperatureZones,
  })  : emitters =
            emitters ?? [_defaultEmitter(emitMaterial ?? Material.water.index)],
        gates = gates ?? const [],
        portals = portals ?? const [],
        temperatureZones = temperatureZones ?? const [],
        grid = Grid(SimConstants.gridWidth, SimConstants.gridHeight),
        rng = DeterministicRng(seed) {
    rules = Rules(rng);
  }

  /// 상단 중앙 밴드 단일 무한 방출구 (기본 데모 씬).
  static EmitterConfig _defaultEmitter(int material) {
    final cx = SimConstants.gridWidth ~/ 2;
    return EmitterConfig(
      x: cx - SimConstants.emitterHalfWidth,
      y: SimConstants.emitterRow,
      width: SimConstants.emitterHalfWidth * 2 + 1,
      materialId: material,
      intervalTicks: SimConstants.emitIntervalTicks,
    );
  }

  /// 방출구 수.
  int get emitterCount => emitters.length;

  /// i번 방출구의 남은 방출 셀 수 (무한이면 null). 유한 방출 UI·실패 판정용.
  int? emitterRemaining(int i) => emitters[i].remaining;

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
    for (final e in emitters) {
      e.resetRuntime();
    }
  }

  /// 상전이 관찰 콜백 (M5 폴리시). shell-ui가 결빙 crackle·증발 puff 등 SFX/VFX를 여기에
  /// 연결한다. 관찰 전용(결정성 무영향), null이면 비용 0. reset()이 지우지 않는다.
  PhaseChangeCallback? get onPhaseChange => rules.onPhaseChange;
  set onPhaseChange(PhaseChangeCallback? cb) => rules.onPhaseChange = cb;

  /// 중력이 반전(위 방향)되어 있는가 (GDD 6).
  bool get gravityInverted => rules.gravityInverted;

  /// 전역 중력 반전 토글 (GDD 6). gameplay의 중력 반전 버튼이 호출한다. 입력 시퀀스의
  /// 일부이므로 결정성 로그에 기록되어야 한다(계약). reset()은 기본(아래)으로 되돌린다.
  void setGravityInverted(bool inverted) => rules.setGravityInverted(inverted);

  /// 한 틱: 방출 → 상전이(룬·온도 존) → 게이트 → 이동 → 포탈. 순서 고정(결정성).
  void tick() {
    _emit();
    rules.step(grid, gates: gates, portals: portals, zones: temperatureZones);
    tickCount++;
  }

  /// 방출: 낱알 흩뿌림 (2026-07-19 사용자 디렉션 — "일렬 막대" 방지).
  ///
  /// 이전에는 intervalTicks마다 밴드 전체(한 줄)를 동시에 채워 낙하 스트림이
  /// 가로 막대들의 행렬로 보였다. 지금은 **매 틱** 평균 처리량(width/intervalTicks)을
  /// 유지하며 밴드 내 결정성 RNG가 고른 무작위 열에 낱알을 떨어뜨린다 —
  /// 원작(sugar, sugar)의 알갱이 stream 질감. ashRatio·유한 잔량 규칙은 동일.
  void _emit() {
    for (final e in emitters) {
      if (e.exhausted) continue;
      final expected = e.width / e.intervalTicks;
      var count = expected.floor();
      final frac = expected - count;
      if (frac > 0 && rng.nextDouble() < frac) count++;
      for (var n = 0; n < count; n++) {
        if (e.exhausted) break;
        final x = e.x + (e.width <= 1 ? 0 : rng.nextInt(e.width));
        if (!grid.inBounds(x, e.y)) continue;
        if (grid.get(x, e.y) != Material.empty.index) continue;
        final id = (e.ashRatio > 0 && rng.nextDouble() < e.ashRatio)
            ? Material.ash.index
            : e.materialId;
        grid.set(x, e.y, id);
        if (!e.isInfinite) e.remaining = e.remaining! - 1;
      }
    }
  }

  /// (x, y)를 EMPTY로 비우고 비어진 물질 ID를 반환한다. 이미 EMPTY거나 범위 밖이면
  /// 0(EMPTY.index). RNG 미사용 = 결정적. 플라스크 착수 소비용 (M2 gameplay 계약).
  /// 무엇을 소비할지(매칭/통과)의 판정은 호출자 책임 — 여기선 무조건 비운다.
  int consumeCell(int x, int y) {
    if (!grid.inBounds(x, y)) return Material.empty.index;
    final id = grid.get(x, y);
    if (id == Material.empty.index) return Material.empty.index;
    grid.set(x, y, Material.empty.index);
    return id;
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
  /// [maxCells]: 이번 호출에서 배치할 EMPTY 셀 수 상한. 잔량까지만 칠하고 멈춘다
  /// (부분 배치 cap — 잉크 부족 시 잔량 소진 지점에서 선이 멈추는 GDD 4.2 청구 모델).
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
  /// 예산 cap 사전 계산·사후 검증용. 직후 [extendStroke]가 같은 좌표로 칠하면
  /// (그 사이 그리드 변화가 없는 한) 이 값(또는 maxCells cap)만큼 배치된다.
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
