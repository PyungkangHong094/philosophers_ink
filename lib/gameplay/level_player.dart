/// 레벨 한 판을 실제로 플레이하는 위젯 (디버그 수준 UI, 폴리시 금지 — M4+ 셸이 대체).
///
/// [Level] 하나를 받아 코어 루프(잉크 드로잉 → 시뮬 → 플라스크 판정 → 클리어/실패
/// → 별점)를 돌린다. main.dart(에셋 순회)와 인앱 에디터(테스트 플레이)가 공유한다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/constants.dart';
import '../core/game_loop.dart';
import '../level/level_model.dart';
import '../render/palette.dart';
import '../render/world_painter.dart';
import 'debug_hud.dart';
import 'level_session.dart';

enum PlayPhase { playing, cleared, failed }

class _Outcome {
  final PlayPhase phase;
  final int stars;
  const _Outcome(this.phase, {this.stars = 0});
}

class LevelPlayer extends StatefulWidget {
  final Level level;

  /// "다음" 버튼 콜백. null이면 클리어 시 "다음"을 숨긴다.
  final VoidCallback? onNext;

  /// 좌상단 뒤로가기 등 부가 액션(에디터 복귀). null이면 없음.
  final VoidCallback? onExit;

  const LevelPlayer({super.key, required this.level, this.onNext, this.onExit});

  @override
  State<LevelPlayer> createState() => _LevelPlayerState();
}

class _LevelPlayerState extends State<LevelPlayer>
    with SingleTickerProviderStateMixin {
  late LevelSession _session;
  late final GameLoop _loop;
  late final Palette _palette;
  late final WorldImageSource _imageSource;
  late final Uint8List _rgba;
  late final Ticker _ticker;

  final ValueNotifier<_Outcome> _outcome =
      ValueNotifier<_Outcome>(const _Outcome(PlayPhase.playing));
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  int? _activeStrokeId;
  (int, int)? _lastCell;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _session = LevelSession(widget.level);
    _palette = Palette();
    _rgba = Uint8List(SimConstants.gridWidth * SimConstants.gridHeight * 4);
    _imageSource = WorldImageSource(
      width: SimConstants.gridWidth,
      height: SimConstants.gridHeight,
    );
    _loop = GameLoop(onTick: () => _session.tick());
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _imageSource.dispose();
    _outcome.dispose();
    _frameTick.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    _loop.advance(elapsed);
    _palette.writeRgba(_session.game.grid.cells, _rgba);
    _imageSource.update(_rgba);
    _frameTick.value++;

    if (_outcome.value.phase == PlayPhase.playing) {
      if (_session.isFailed) {
        _outcome.value = const _Outcome(PlayPhase.failed);
      } else if (_session.isCleared) {
        _outcome.value = _Outcome(PlayPhase.cleared, stars: _session.result.stars);
      }
    }
  }

  bool get _canDraw => _outcome.value.phase == PlayPhase.playing;

  (int, int)? _cellAt(Offset local) {
    if (_viewSize == Size.zero) return null;
    final vp = GridViewport.fit(
        _viewSize, SimConstants.gridWidth, SimConstants.gridHeight);
    return vp.toGrid(local);
  }

  void _chargedExtend(int strokeId, int x0, int y0, int x1, int y1) {
    final budget = _session.ink.selectedRemaining;
    if (budget <= 0) return;
    final placed =
        _session.game.extendStroke(strokeId, x0, y0, x1, y1, maxCells: budget);
    _session.ink.chargePlaced(placed);
  }

  void _onPanStart(DragStartDetails d) {
    if (!_canDraw) return;
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    final ink = _session.ink.selected;
    if (ink == null || !_session.ink.canDraw) return;
    final id = _session.game.beginStroke(ink);
    _chargedExtend(id, cell.$1, cell.$2, cell.$1, cell.$2);
    _activeStrokeId = id;
    _lastCell = cell;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_canDraw) return;
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    if (_activeStrokeId == null) {
      final ink = _session.ink.selected;
      if (ink == null || !_session.ink.canDraw) return;
      final id = _session.game.beginStroke(ink);
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
    if (!_canDraw) return;
    final cell = _cellAt(d.localPosition);
    if (cell != null) _session.game.deleteStrokeAt(cell.$1, cell.$2);
  }

  void _retry() {
    _session.reset();
    _loop.reset();
    _activeStrokeId = null;
    _lastCell = null;
    _outcome.value = const _Outcome(PlayPhase.playing);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Color(widget.level.background),
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
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frameTick,
                builder: (context, _, _) =>
                    CustomPaint(painter: FlaskOverlayPainter(_session)),
              ),
            ),
          ),
          Positioned(
            top: topPad + 8,
            left: 8,
            child: _LevelInfo(session: _session, frameTick: _frameTick),
          ),
          Positioned(
            top: topPad + 8,
            right: 8,
            child: Row(
              children: [
                if (widget.onExit != null)
                  _MiniButton(label: 'EXIT', onTap: widget.onExit!),
                if (widget.onExit != null) const SizedBox(width: 6),
                _MiniButton(label: 'RESET', onTap: _retry),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: Center(child: InkHud(controller: _session.ink)),
          ),
          ValueListenableBuilder<_Outcome>(
            valueListenable: _outcome,
            builder: (context, o, _) => _OutcomeBanner(
              outcome: o,
              onRetry: _retry,
              onNext: widget.onNext,
            ),
          ),
        ],
      ),
    );
  }
}

/// 플라스크 영역을 윤곽 + count/goal 텍스트로 그린다 (디버그 오버레이).
class FlaskOverlayPainter extends CustomPainter {
  final LevelSession session;
  FlaskOverlayPainter(this.session);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFC9A227);

    for (final flask in session.flasks.flasks) {
      final s = flask.spec;
      final rect = Rect.fromLTWH(
        vp.offsetX + s.x * vp.scale,
        vp.offsetY + s.y * vp.scale,
        s.w * vp.scale.toDouble(),
        s.h * vp.scale.toDouble(),
      );
      canvas.drawRect(rect, border);
      final label =
          flask.isFailed ? 'X' : '${flask.count}/${s.goal}${s.pure ? '!' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFF2EDDF),
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, rect.top - 15));
    }
  }

  @override
  bool shouldRepaint(FlaskOverlayPainter oldDelegate) => true;
}

class _LevelInfo extends StatelessWidget {
  final LevelSession session;
  final ValueListenable<int> frameTick;
  const _LevelInfo({required this.session, required this.frameTick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: frameTick,
        builder: (context, _, _) {
          final progress = session.flasks.flasks
              .map((f) => '${f.count}/${f.spec.goal}')
              .join('  ');
          return DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFB79A6A),
              fontSize: 11,
              height: 1.35,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LV ${session.level.meta.id} ${session.level.meta.name}'),
                Text('flasks $progress'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final _Outcome outcome;
  final VoidCallback onRetry;
  final VoidCallback? onNext;
  const _OutcomeBanner({
    required this.outcome,
    required this.onRetry,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    if (outcome.phase == PlayPhase.playing) return const SizedBox.shrink();
    final isCleared = outcome.phase == PlayPhase.cleared;
    return Positioned.fill(
      child: Container(
        color: const Color(0xE6050505),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isCleared ? '정제 완료' : '오염',
              style: const TextStyle(
                color: Color(0xFFF2EDDF),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isCleared) ...[
              const SizedBox(height: 12),
              Text(
                '★' * outcome.stars + '☆' * (3 - outcome.stars),
                style: const TextStyle(color: Color(0xFFC9A227), fontSize: 26),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text('재시작 필요',
                  style: TextStyle(color: Color(0xFF9C968A), fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniButton(label: '다시', onTap: onRetry),
                if (isCleared && onNext != null) ...[
                  const SizedBox(width: 12),
                  _MiniButton(label: '다음', onTap: onNext!, gold: true),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool gold;
  const _MiniButton(
      {required this.label, required this.onTap, this.gold = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: gold ? const Color(0xFFC9A227) : const Color(0xCC000000),
          border: Border.all(color: const Color(0xFF29271F)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: gold ? const Color(0xFF050505) : const Color(0xFFCDBFA0),
            fontSize: 12,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
