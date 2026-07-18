/// 인게임 플레이 화면 — 디버그 level_player를 대체하는 정식 셸 인게임 (GDD 8.3/8.4).
///
/// [LevelSession](게임플레이 소유)과 sim/render 공개 API만 재사용해 코어 루프를 돌리고,
/// 정식 HUD(하단 잉크 팔레트 바·목표 플라스크·상단 일시정지/재시작·대형 레벨 번호),
/// 클리어/실패/일시정지 오버레이를 얹는다. 입력 처리는 세션 공개 API 호출뿐이다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/constants.dart';
import '../../core/game_loop.dart';
import '../../gameplay/level_session.dart';
import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/progress.dart';
import '../../render/palette.dart';
import '../../render/world_painter.dart';
import '../settings_controller.dart';
import '../tokens.dart';
import 'clear_overlay.dart';
import 'ink_palette_bar.dart';
import 'pause_overlay.dart';

enum _Phase { playing, cleared, failed }

class _Outcome {
  final _Phase phase;
  final int stars;
  const _Outcome(this.phase, {this.stars = 0});
}

class PlayScreen extends StatefulWidget {
  final LevelEntry entry;
  final GameProgress progress;
  final SettingsController settings;

  /// "다음 레벨" 콜백. null이면 다음이 없거나 잠김 — 버튼 숨김.
  final VoidCallback? onNext;

  const PlayScreen({
    super.key,
    required this.entry,
    required this.progress,
    required this.settings,
    this.onNext,
  });

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen>
    with SingleTickerProviderStateMixin {
  late LevelSession _session;
  late final GameLoop _loop;
  late final Palette _palette;
  late final WorldImageSource _imageSource;
  late final Uint8List _rgba;
  late final Ticker _ticker;

  final ValueNotifier<_Outcome> _outcome =
      ValueNotifier<_Outcome>(const _Outcome(_Phase.playing));
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  bool _paused = false;
  bool _recorded = false;

  int? _activeStrokeId;
  (int, int)? _lastCell;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _session = LevelSession(widget.entry.level);
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

  bool get _simRunning => !_paused && _outcome.value.phase == _Phase.playing;

  void _onFrame(Duration elapsed) {
    // 일시정지·클리어·실패 중에는 시뮬을 멈춘다. GameLoop이 누적기를
    // maxFrameAccumSeconds로 클램프하므로 복귀 시 큰 델타로 튀지 않는다.
    if (!_simRunning) return;

    _loop.advance(elapsed);
    _palette.writeRgba(_session.game.grid.cells, _rgba);
    _imageSource.update(_rgba);
    _frameTick.value++;

    if (_session.isFailed) {
      _outcome.value = const _Outcome(_Phase.failed);
    } else if (_session.isCleared) {
      final stars = _session.result.stars;
      _outcome.value = _Outcome(_Phase.cleared, stars: stars);
      _recordResult(stars);
    }
  }

  void _recordResult(int stars) {
    if (_recorded) return;
    _recorded = true;
    widget.progress
        .record(widget.entry.id, cleared: true, stars: stars);
  }

  bool get _canDraw => _simRunning;

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
    _recorded = false;
    _paused = false;
    _outcome.value = const _Outcome(_Phase.playing);
    setState(() {});
  }

  void _exit() => Navigator.of(context).maybePop();

  String get _eyebrow {
    final chapter = chapterForLevel(widget.entry.id);
    final chapterName = chapter?.latin ?? 'INK';
    return '$chapterName · LV ${widget.entry.id}';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final reduced = widget.settings.reducedMotion ||
        MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: Color(widget.entry.level.background),
      body: Stack(
        children: [
          // 시뮬 캔버스.
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
          // 플라스크 목표 오버레이.
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frameTick,
                builder: (context, _, child) =>
                    CustomPaint(painter: _FlaskHudPainter(_session)),
              ),
            ),
          ),
          // 대형 레벨 번호 (배경 위 타이포, GDD 8.3).
          Positioned(
            top: topPad + InkSpace.sm,
            left: InkSpace.md,
            child: IgnorePointer(
              child: Text(
                '${widget.entry.id}',
                style: InkText.displayM.copyWith(
                  color: InkColor.parchment.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          // 상단 우측: 일시정지 + 재시작 (+ 중력 반전).
          Positioned(
            top: topPad + InkSpace.sm,
            right: InkSpace.sm,
            child: Row(
              children: [
                if (_session.hasGravityFlip) ...[
                  _HudIconButton(
                    icon: Icons.swap_vert,
                    label: '중력',
                    onTap: () {
                      if (_canDraw) {
                        _session.toggleGravity();
                        widget.settings.hapticSelection();
                      }
                    },
                  ),
                  const SizedBox(width: InkSpace.sm),
                ],
                _HudIconButton(
                  icon: Icons.refresh,
                  label: '재시작',
                  onTap: _retry,
                ),
                const SizedBox(width: InkSpace.sm),
                _HudIconButton(
                  icon: Icons.pause,
                  label: '일시정지',
                  onTap: () => setState(() => _paused = true),
                ),
              ],
            ),
          ),
          // 하단 잉크 팔레트 바.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + InkSpace.md,
            child: Center(
              child: InkPaletteBar(
                controller: _session.ink,
                onSelect: widget.settings.hapticSelection,
              ),
            ),
          ),
          // 오버레이들.
          ValueListenableBuilder<_Outcome>(
            valueListenable: _outcome,
            builder: (context, o, _) {
              if (o.phase == _Phase.cleared) {
                return ClearOverlay(
                  eyebrow: _eyebrow,
                  stars: o.stars,
                  inkRemainingFraction: _inkRemainingFraction(),
                  inkGaugeLabel: _inkGaugeLabel(),
                  onNext: widget.onNext,
                  onRetry: _retry,
                  reducedMotion: reduced,
                  onStarStamped: widget.settings.hapticLight,
                );
              }
              if (o.phase == _Phase.failed) {
                return FailOverlay(eyebrow: _eyebrow, onRetry: _retry);
              }
              return const SizedBox.shrink();
            },
          ),
          if (_paused)
            PauseOverlay(
              eyebrow: _eyebrow,
              onResume: () => setState(() => _paused = false),
              onRetry: _retry,
              onExit: _exit,
            ),
        ],
      ),
    );
  }

  double _inkRemainingFraction() {
    final b = _session.ink.budget;
    final init = b.totalInitial;
    if (init == 0) return 0;
    return b.totalRemaining / init;
  }

  String _inkGaugeLabel() {
    final b = _session.ink.budget;
    return '잉크 잔량 ${b.totalRemaining} / ${b.totalInitial}';
  }
}

/// 상단 HUD 아이콘 버튼 (일시정지·재시작 등). 무채 — 골드 금지.
class _HudIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HudIconButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: InkSpace.touchTarget,
          height: InkSpace.touchTarget,
          decoration: BoxDecoration(
            color: InkColor.black2,
            border: Border.all(color: InkColor.hairline),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: Icon(icon, color: InkColor.parchment, size: 20),
        ),
      ),
    );
  }
}

/// 플라스크 목표를 윤곽 + count/goal 로 그린다 (정식 HUD 버전, 셸 토큰).
class _FlaskHudPainter extends CustomPainter {
  final LevelSession session;
  _FlaskHudPainter(this.session);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = InkColor.gold;

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
          flask.isFailed ? '✕' : '${flask.count}/${s.goal}${s.pure ? '!' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: InkColor.parchment,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: InkText.tabular,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, rect.top - 16));
    }
  }

  @override
  bool shouldRepaint(_FlaskHudPainter oldDelegate) => true;
}
