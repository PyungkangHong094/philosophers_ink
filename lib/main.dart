import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/constants.dart';
import 'core/game_loop.dart';
import 'core/game_state.dart';
import 'render/palette.dart';
import 'render/world_painter.dart';

void main() => runApp(const PhilosophersInkApp());

class PhilosophersInkApp extends StatelessWidget {
  const PhilosophersInkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: "Philosopher's Ink — M0",
      debugShowCheckedModeBanner: false,
      home: SimSpikeScreen(),
    );
  }
}

/// M0 데모 씬 (GDD 11장 M0): 상단 방출구에서 PRIMA가 낙하하고, 드래그로 석필 선을
/// 그으면 그 위에 입자가 쌓인다. 탭으로 스트로크 삭제. 디버그 오버레이로 계측 표시.
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
  int? _activeStrokeId;
  (int, int)? _lastCell;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _game = GameState();
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

  void _onPanStart(DragStartDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    _activeStrokeId = _game.beginStroke(cell.$1, cell.$2);
    _lastCell = cell;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    if (_activeStrokeId == null) {
      _activeStrokeId = _game.beginStroke(cell.$1, cell.$2);
      _lastCell = cell;
      return;
    }
    final last = _lastCell;
    if (last != null) {
      _game.extendStroke(_activeStrokeId!, last.$1, last.$2, cell.$1, cell.$2);
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
