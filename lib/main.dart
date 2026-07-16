import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/constants.dart';
import 'core/game_loop.dart';
import 'core/game_state.dart';
import 'gameplay/debug_hud.dart';
import 'gameplay/gameplay_constants.dart';
import 'gameplay/ink_budget.dart';
import 'gameplay/ink_controller.dart';
import 'render/palette.dart';
import 'render/world_painter.dart';

void main() => runApp(const PhilosophersInkApp());

class PhilosophersInkApp extends StatelessWidget {
  const PhilosophersInkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: "Philosopher's Ink — M1",
      debugShowCheckedModeBanner: false,
      home: SimSpikeScreen(),
    );
  }
}

/// M1 데모 씬 (GDD 11장 M1-A): 상단 방출구에서 WATER가 낙하한다. 잉크를 골라 드래그하면
/// 석필(WALL)로 물을 가두고, 서리 룬 위에 고인 물이 ICE로 얼어 쌓이며, 화염 룬이 물을
/// STEAM으로 증발시켜 상승시킨다. 탭으로 스트로크 삭제. 디버그 오버레이로 계측 표시.
class SimSpikeScreen extends StatefulWidget {
  const SimSpikeScreen({super.key});

  @override
  State<SimSpikeScreen> createState() => _SimSpikeScreenState();
}

class _SimSpikeScreenState extends State<SimSpikeScreen>
    with SingleTickerProviderStateMixin {
  late final GameState _game;
  late final GameLoop _loop;
  late final Palette _palette;
  late final WorldImageSource _imageSource;
  late final Uint8List _rgba;
  late final Ticker _ticker;

  final ValueNotifier<_DebugStats> _stats =
      ValueNotifier<_DebugStats>(_DebugStats.zero);

  // 드로잉 상태
  late final InkController _ink;
  int? _activeStrokeId;
  (int, int)? _lastCell;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _game = GameState();
    // M1 데모 예산 주입 (M2부터 레벨 JSON이 대체). 셋 다 노출해 병 3개·게이지·선택·숨김 검증.
    _ink = InkController(InkBudget(
      chalk: GameplayConstants.demoChalkBudget,
      heat: GameplayConstants.demoHeatBudget,
      frost: GameplayConstants.demoFrostBudget,
    ));
    _palette = Palette();
    _rgba = Uint8List(_game.grid.cells.length * 4);
    _imageSource = WorldImageSource(
      width: _game.grid.width,
      height: _game.grid.height,
    );
    _loop = GameLoop(onTick: _game.tick);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _imageSource.dispose();
    _stats.dispose();
    _ink.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    final frameSw = Stopwatch()..start();

    final simSw = Stopwatch()..start();
    final ticks = _loop.advance(elapsed);
    simSw.stop();

    final convertSw = Stopwatch()..start();
    _palette.writeRgba(_game.grid.cells, _rgba);
    convertSw.stop();

    // 그리드 → ui.Image 변환은 비동기. 발사 후 잊기(in-flight 가드는 소스 내부).
    _imageSource.update(_rgba);

    final activeParticles = _game.activeCellCount;
    frameSw.stop();

    final simMs = simSw.elapsedMicroseconds / 1000.0;
    _stats.value = _DebugStats(
      simMsFrame: simMs,
      perTickMs: ticks > 0 ? simMs / ticks : 0,
      ticksThisFrame: ticks,
      convertMs: convertSw.elapsedMicroseconds / 1000.0,
      frameMs: frameSw.elapsedMicroseconds / 1000.0,
      activeParticles: activeParticles,
    );
  }

  (int, int)? _cellAt(Offset local) {
    if (_viewSize == Size.zero) return null;
    final vp = GridViewport.fit(_viewSize, _game.grid.width, _game.grid.height);
    return vp.toGrid(local);
  }

  /// 잉크 예산 한도 내에서만 세그먼트를 배치하고 실제 배치 셀 수를 차감한다.
  /// 잔량을 maxCells 상한으로 넘겨 잔량만큼만 칠하므로 배치량과 차감량이 정확히
  /// 일치한다 (부분 배치 cap 모델, GDD 4.2). 잔량이 소진되면 선이 그 지점에서
  /// 멈춘다. 삭제 시 미반환은 sim이 보장.
  void _chargedExtend(int strokeId, int x0, int y0, int x1, int y1) {
    final budget = _ink.selectedRemaining;
    if (budget <= 0) return;
    final placed =
        _game.extendStroke(strokeId, x0, y0, x1, y1, maxCells: budget);
    _ink.chargePlaced(placed);
  }

  void _onPanStart(DragStartDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    final ink = _ink.selected;
    if (ink == null || !_ink.canDraw) return; // 선택 없거나 예산 0 → 거부
    final id = _game.beginStroke(ink);
    _chargedExtend(id, cell.$1, cell.$2, cell.$1, cell.$2);
    _activeStrokeId = id;
    _lastCell = cell;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    if (_activeStrokeId == null) {
      final ink = _ink.selected;
      if (ink == null || !_ink.canDraw) return;
      final id = _game.beginStroke(ink);
      _chargedExtend(id, cell.$1, cell.$2, cell.$1, cell.$2);
      _activeStrokeId = id;
      _lastCell = cell;
      return;
    }
    final last = _lastCell;
    if (last != null) {
      _chargedExtend(_activeStrokeId!, last.$1, last.$2, cell.$1, cell.$2);
    }
    _lastCell = cell;
  }

  void _onPanEnd(DragEndDetails d) {
    _activeStrokeId = null;
    _lastCell = null;
  }

  void _onTapUp(TapUpDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell != null) _game.deleteStrokeAt(cell.$1, cell.$2);
  }

  void _reset() {
    _game.reset();
    _loop.reset();
    _ink.reset(); // 예산·선택 복원 (재시작 안전, GDD 10.5)
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      // EMPTY 색과 동일 — 그리드가 화면을 다 못 채워도 배경이 이어진다.
      backgroundColor: const Color(0xFF1D1418),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onTapUp: _onTapUp,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: WorldPainter(_imageSource),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: topPad + 8,
            left: 8,
            child: _DebugOverlay(stats: _stats),
          ),
          Positioned(
            top: topPad + 8,
            right: 8,
            child: _ResetButton(onPressed: _reset),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: Center(child: InkHud(controller: _ink)),
          ),
        ],
      ),
    );
  }
}

/// 디버그 오버레이. QA가 이 수치(틱 시간·프레임 시간·활성 입자 수)를 읽는다.
class _DebugOverlay extends StatelessWidget {
  final ValueListenable<_DebugStats> stats;
  const _DebugOverlay({required this.stats});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_DebugStats>(
      valueListenable: stats,
      builder: (context, s, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFB79A6A),
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.35,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'grid ${SimConstants.gridWidth}x${SimConstants.gridHeight}'
                  ' @${SimConstants.tickRateHz}Hz',
                ),
                Text(
                  'sim  ${s.simMsFrame.toStringAsFixed(2)} ms/frame'
                  '  (${s.ticksThisFrame} tick,'
                  ' ${s.perTickMs.toStringAsFixed(2)} ms/tick)',
                ),
                Text('conv ${s.convertMs.toStringAsFixed(2)} ms'),
                Text('frame ${s.frameMs.toStringAsFixed(2)} ms'),
                Text('active ${s.activeParticles}'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResetButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ResetButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC000000),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            'RESET',
            style: TextStyle(
              color: Color(0xFFCDBFA0),
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 오버레이 표시용 불변 계측 스냅샷.
class _DebugStats {
  final double simMsFrame;
  final double perTickMs;
  final int ticksThisFrame;
  final double convertMs;
  final double frameMs;
  final int activeParticles;

  const _DebugStats({
    required this.simMsFrame,
    required this.perTickMs,
    required this.ticksThisFrame,
    required this.convertMs,
    required this.frameMs,
    required this.activeParticles,
  });

  static const _DebugStats zero = _DebugStats(
    simMsFrame: 0,
    perTickMs: 0,
    ticksThisFrame: 0,
    convertMs: 0,
    frameMs: 0,
    activeParticles: 0,
  );
}
