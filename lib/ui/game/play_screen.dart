/// 인게임 플레이 화면 — 디버그 level_player를 대체하는 정식 셸 인게임 (GDD 8.3/8.4).
///
/// [LevelSession](게임플레이 소유)과 sim/render 공개 API만 재사용해 코어 루프를 돌리고,
/// 정식 HUD(하단 잉크 팔레트 바·목표 플라스크·상단 일시정지/재시작·대형 레벨 번호),
/// 클리어/실패/일시정지 오버레이를 얹는다. 입력 처리는 세션 공개 API 호출뿐이다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_service.dart';
import '../../audio/sound_tokens.dart';
import '../../core/constants.dart';
import '../../core/game_loop.dart';
import '../../gameplay/level_session.dart';
import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/onboarding.dart';
import '../../meta/progress.dart';
import '../../render/palette.dart';
import '../../render/world_painter.dart';
import '../../sim/materials.dart';
import '../onboarding/onboarding_text.dart';
import '../onboarding/onboarding_widgets.dart';
import '../settings_controller.dart';
import '../tokens.dart';
import 'clear_overlay.dart';
import 'ink_palette_bar.dart';
import 'pause_overlay.dart';

/// 첫 조작 가이드 종류.
enum _GuideKind { none, stroke, gravity }

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
  final AudioService audio;
  final OnboardingState onboarding;

  /// "다음 레벨" 콜백. null이면 다음이 없거나 잠김 — 버튼 숨김.
  final VoidCallback? onNext;

  const PlayScreen({
    super.key,
    required this.entry,
    required this.progress,
    required this.settings,
    required this.audio,
    required this.onboarding,
    this.onNext,
  });

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  int _ambientFrame = 0;

  /// 플라스크 라벨 TextPainter 캐시 — 라벨 문자열이 바뀔 때만 재생성 (감사 P3-2).
  final _FlaskLabelCache _flaskLabels = _FlaskLabelCache();

  // ---- 온보딩 (GDD 7.2) ----
  bool _goalVisible = true;
  bool _guideVisible = false;
  _GuideKind _guide = _GuideKind.none;
  bool _gaugeEmphasize = false;
  bool _sawFirstInput = false;
  bool _explainStars = false; // 이번 클리어가 첫 클리어라 별점 설명을 노출하는가.
  Timer? _goalTimer;
  Timer? _guideTimer;
  Timer? _gaugeTimer;

  /// 목표 배너 자동 소멸 시간.
  static const Duration _goalDwell = Duration(seconds: 3);

  /// 게이지 강조 지속 시간.
  static const Duration _gaugeDwell = Duration(milliseconds: 1200);

  bool get _isTutorialChapter => widget.entry.chapter == 1;

  @override
  void initState() {
    super.initState();
    // 플라스크 착수 이벤트 → 착수 틱(카운트업 동기, GDD 9.2). 상별 피치.
    _session = LevelSession(
      widget.entry.level,
      onSettle: (e) => widget.audio.flaskFill(e.phase),
    );
    _palette = Palette();
    _rgba = Uint8List(SimConstants.gridWidth * SimConstants.gridHeight * 4);
    _imageSource = WorldImageSource(
      width: SimConstants.gridWidth,
      height: SimConstants.gridHeight,
    );
    _loop = GameLoop(onTick: () => _session.tick());
    _ticker = createTicker(_onFrame)..start();
    WidgetsBinding.instance.addObserver(this); // 앱 백그라운드 전환 감지.
    _setupOnboarding();
  }

  /// 목표 배너 자동 소멸 타이머 + (튜토리얼 챕터) 미조작 첫 조작 가이드 예약.
  ///
  /// 미시청 가이드가 있는 판(첫 경험)에서는 3초 방치를 기다리지 않는다 — 빠른
  /// 플레이어는 즉시 터치해서 "3초 뒤" 안내를 평생 못 보기 때문(실플레이 피드백).
  /// 이때 목표 배너도 자동 소멸 없이 첫 조작까지 유지한다.
  void _setupOnboarding() {
    _GuideKind pending = _GuideKind.none;
    if (_isTutorialChapter) {
      final ob = widget.onboarding;
      // 레벨 1~2: 스트로크 가이드. 중력 기믹 레벨: 중력 가이드. (각 1회만.)
      if (widget.entry.id <= 2 && !ob.hasSeen(OnboardingKey.stroke)) {
        pending = _GuideKind.stroke;
      } else if (_session.hasGravityFlip &&
          !ob.hasSeen(OnboardingKey.gravity)) {
        pending = _GuideKind.gravity;
      }
    }

    if (pending == _GuideKind.none) {
      // 첫 경험이 아니면 기존 대로: 배너 3초 자동 소멸, 가이드 없음.
      _goalTimer = Timer(_goalDwell, () {
        if (mounted) setState(() => _goalVisible = false);
      });
      return;
    }

    // 첫 경험: 가이드 즉시 노출(짧은 호흡 뒤), 목표 배너는 첫 조작까지 유지.
    _guide = pending;
    _guideTimer = Timer(const Duration(milliseconds: 600), () {
      final blockedByInput = pending == _GuideKind.stroke && _sawFirstInput;
      if (mounted && !blockedByInput) setState(() => _guideVisible = true);
    });
  }

  /// 첫 조작(스트로크) 시 온보딩 반응: 목표·스트로크 가이드 소멸 + 게이지 힌트 1회.
  void _onFirstInput() {
    if (_sawFirstInput) return;
    _sawFirstInput = true;
    setState(() {
      _goalVisible = false;
      if (_guide == _GuideKind.stroke) {
        _guideVisible = false;
        widget.onboarding.markSeenOnce(OnboardingKey.stroke);
      }
    });
    // 게이지 이해 힌트 — 튜토리얼 챕터에서 1회만.
    if (_isTutorialChapter &&
        widget.onboarding.markSeenOnce(OnboardingKey.gauge)) {
      setState(() => _gaugeEmphasize = true);
      _gaugeTimer = Timer(_gaugeDwell, () {
        if (mounted) setState(() => _gaugeEmphasize = false);
      });
    }
  }

  /// 중력 반전 첫 사용 시 중력 가이드 소멸.
  void _onGravityUsed() {
    if (_guide == _GuideKind.gravity && _guideVisible) {
      setState(() => _guideVisible = false);
      widget.onboarding.markSeenOnce(OnboardingKey.gravity);
    }
  }

  @override
  void dispose() {
    _goalTimer?.cancel();
    _guideTimer?.cancel();
    _gaugeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.audio.stopAll(); // 화면 이탈 시 루프성 재생(앰비언트 등) 전부 정지 — 전역 잔존 방지.
    _ticker.dispose(); // 프레임 정지 먼저 — 이후 세션을 건드리지 않는다.
    _session.dispose(); // InkController(ChangeNotifier) 등 세션 소유 자원 해제 (감사 P2-2).
    _imageSource.dispose();
    _outcome.dispose();
    _frameTick.dispose();
    _flaskLabels.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 포그라운드를 벗어나면 시뮬을 멈추고 루프성 재생을 정지한다(백그라운드 지속 소음 방지).
    if (state != AppLifecycleState.resumed) {
      widget.audio.stopAll();
      if (!_paused && _outcome.value.phase == _Phase.playing && mounted) {
        setState(() => _paused = true);
      }
    }
  }

  bool get _simRunning => !_paused && _outcome.value.phase == _Phase.playing;

  void _onFrame(Duration elapsed) {
    // 일시정지·클리어·실패 중에는 시뮬을 멈춘다. GameLoop이 누적기를
    // maxFrameAccumSeconds로 클램프하므로 복귀 시 큰 델타로 튀지 않는다.
    if (!_simRunning) {
      widget.audio.stopAmbient();
      return;
    }

    _loop.advance(elapsed);
    _palette.writeRgba(_session.game.grid.cells, _rgba);
    _imageSource.update(_rgba);
    _frameTick.value++;

    // 물질 앰비언트 그레인 — 활성 셀 밀도로 볼륨 변조 (샘플 스로틀, GDD 9.2).
    // 기본 OFF(드론 "지잉" 방지) — 켜질 때만 그리드를 스캔한다.
    if (SfxSpec.ambientGrainEnabled &&
        ++_ambientFrame % SfxSpec.grainSampleEveryFrames == 0) {
      widget.audio.setAmbientDensity(_ambientDensity());
    }

    if (_session.isFailed) {
      _outcome.value = const _Outcome(_Phase.failed);
      widget.audio.stopAmbient();
      widget.audio.fail();
    } else if (_session.isCleared) {
      final stars = _session.result.stars;
      // 첫 클리어면 별점 설명을 1회 노출(이후 영속으로 숨김).
      _explainStars = widget.onboarding.markSeenOnce(OnboardingKey.firstClear);
      _outcome.value = _Outcome(_Phase.cleared, stars: stars);
      _recordResult(stars);
      widget.audio.stopAmbient();
      if (isOperatioLevel(widget.entry.id)) {
        widget.audio.operatioStinger();
      } else {
        widget.audio.clearStinger();
      }
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
    if (placed > 0) widget.audio.stroke(); // 드로잉 획음 (내부 스로틀).
  }

  /// 활성 셀 밀도(0~1) — 동적 카테고리(입자·액체·기체) 셀 수 / 기준. 앰비언트 그레인 변조.
  double _ambientDensity() {
    final cells = _session.game.grid.cells;
    var n = 0;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == 0) continue;
      switch (propsOf(c).category) {
        case MaterialCategory.particle:
        case MaterialCategory.liquid:
        case MaterialCategory.gas:
          n++;
        case MaterialCategory.none:
        case MaterialCategory.staticSolid:
          break;
      }
    }
    return (n / SfxSpec.grainRefCells).clamp(0.0, 1.0);
  }

  void _onPanStart(DragStartDetails d) {
    if (!_canDraw) return;
    _onFirstInput();
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
    _onFirstInput();
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
      // 자식이 전부 Positioned라 fit 미지정 시 느슨한 제약에서 Stack이 0×0으로
      // 붕괴한다(실기기 블랙스크린의 원인). expand로 화면 크기를 강제한다.
      body: Stack(
        fit: StackFit.expand,
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
                builder: (context, _, child) => CustomPaint(
                    painter: _FlaskHudPainter(_session, _flaskLabels)),
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
                        _onGravityUsed();
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
                emphasizeCount: _gaugeEmphasize,
                onSelect: () {
                  widget.settings.hapticSelection();
                  widget.audio.uiTap();
                },
              ),
            ),
          ),
          // 목표 배너 (상단, 3초/첫 터치 후 페이드). 대형 레벨 번호 아래.
          Positioned(
            top: topPad + InkSpace.xl + InkSpace.md,
            left: InkSpace.md,
            right: InkSpace.md,
            child: Align(
              alignment: Alignment.topCenter,
              child: GoalBanner(
                text: goalLine(widget.entry.level),
                visible: _goalVisible,
              ),
            ),
          ),
          // 첫 조작 가이드 (튜토리얼 챕터, 미조작 3초 후).
          if (_guideVisible && _guide != _GuideKind.none)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad + 140,
              child: Center(
                child: FirstOpGuide(
                  text: _guide == _GuideKind.gravity
                      ? OnboardingCopy.gravityGuide
                      : OnboardingCopy.strokeGuide,
                  icon: _guide == _GuideKind.gravity
                      ? Icons.swap_vert
                      : Icons.gesture,
                  reducedMotion: reduced,
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
                  // 첫 클리어에만 별점 설명 1줄 + 이번 판 사용량/임계.
                  starHelp: _explainStars ? OnboardingCopy.starExplain : null,
                  usageLine: clearUsageLine(
                      widget.entry.level, _session.ink.budget.totalUsed),
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
              muted: !widget.settings.sound,
              onToggleMute: () =>
                  setState(() => widget.settings.sound = !widget.settings.sound),
              thresholdLine: starThresholdLine(widget.entry.level),
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

/// 플라스크 라벨(count/goal) TextPainter 캐시 — 라벨이 바뀔 때만 재레이아웃 (감사 P3-2).
/// 프레임당 새 TextPainter 할당을 피한다. State가 소유·dispose한다.
class _FlaskLabelCache {
  static const TextStyle _style = TextStyle(
    color: InkColor.parchment,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontFeatures: InkText.tabular,
  );

  final Map<int, ({String label, TextPainter tp})> _entries = {};

  /// 플라스크 [index]의 [label] TextPainter — 라벨 동일 시 캐시 재사용.
  TextPainter painterFor(int index, String label) {
    final cur = _entries[index];
    if (cur != null && cur.label == label) return cur.tp;
    cur?.tp.dispose();
    final tp = TextPainter(
      text: TextSpan(text: label, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    _entries[index] = (label: label, tp: tp);
    return tp;
  }

  void dispose() {
    for (final e in _entries.values) {
      e.tp.dispose();
    }
    _entries.clear();
  }
}

/// 플라스크 목표를 윤곽 + count/goal 로 그린다 (정식 HUD 버전, 셸 토큰).
class _FlaskHudPainter extends CustomPainter {
  final LevelSession session;
  final _FlaskLabelCache labels;
  _FlaskHudPainter(this.session, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = InkColor.gold;

    final flasks = session.flasks.flasks;
    for (var i = 0; i < flasks.length; i++) {
      final flask = flasks[i];
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
      labels.painterFor(i, label).paint(canvas, Offset(rect.left, rect.top - 16));
    }
  }

  @override
  bool shouldRepaint(_FlaskHudPainter oldDelegate) => true;
}
