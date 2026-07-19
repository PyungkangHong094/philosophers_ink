/// 인게임 플레이 화면 — 디버그 level_player를 대체하는 정식 셸 인게임 (GDD 8.3/8.4).
///
/// [LevelSession](게임플레이 소유)과 sim/render 공개 API만 재사용해 코어 루프를 돌리고,
/// 정식 HUD(하단 잉크 팔레트 바·목표 플라스크·상단 일시정지/재시작·대형 레벨 번호),
/// 클리어/실패/일시정지 오버레이를 얹는다. 입력 처리는 세션 공개 API 호출뿐이다.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_service.dart';
import '../../audio/sound_tokens.dart';
import '../../core/constants.dart';
import '../../core/game_loop.dart';
import '../../gameplay/level_session.dart';
import '../../level/level_model.dart' show FlaskState;
import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/onboarding.dart';
import '../../meta/progress.dart';
import '../../render/world_painter.dart';
import '../../sim/materials.dart';
import '../onboarding/onboarding_text.dart';
import '../onboarding/onboarding_widgets.dart';
import '../settings_controller.dart';
import '../tokens.dart';
import 'clear_overlay.dart';
import 'exhaust_nudge.dart';
import 'hud_format.dart';
import 'ink_palette_bar.dart';
import 'pause_overlay.dart';

/// 첫 조작 가이드 종류.
enum _GuideKind { none, stroke, gravity }

// 상전이 SFX 매핑용 물질 ID (Material enum 인덱스 — switch case는 const int 필요).
const int _kIce = 5; // Material.ice
const int _kSteam = 7; // Material.steam
const int _kStone = 10; // Material.stone

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
  int _clearTicks = 0; // 클리어 시점의 시뮬 틱(소요 시간 표시).
  Timer? _goalTimer;
  Timer? _guideTimer;
  Timer? _gaugeTimer;

  // 잉크 소진 넛지 (P2) — 모든 잉크 0 + 미클리어로 8초 방치 시 재시작 유도.
  bool _exhaustNudge = false;
  bool _exhaustScheduled = false;
  Timer? _exhaustTimer;
  static const Duration _exhaustDelay = Duration(seconds: 8);

  /// 목표 배너 자동 소멸 시간.
  static const Duration _goalDwell = Duration(seconds: 3);

  /// 게이지 강조 지속 시간.
  static const Duration _gaugeDwell = Duration(milliseconds: 1200);

  bool get _isTutorialChapter => widget.entry.chapter == 1;

  @override
  void initState() {
    super.initState();
    // 플라스크 착수 이벤트 → 착수 틱(카운트업 동기, GDD 9.2). 상별 피치 + 채움 진행도로 램프.
    _session = LevelSession(
      widget.entry.level,
      onSettle: (e) {
        final flasks = _session.flasks.flasks;
        final goal = (e.flaskIndex >= 0 && e.flaskIndex < flasks.length)
            ? flasks[e.flaskIndex].spec.goal
            : 0;
        final count = (e.flaskIndex >= 0 && e.flaskIndex < flasks.length)
            ? flasks[e.flaskIndex].count
            : 0;
        final progress = goal > 0 ? count / goal : 0.0;
        widget.audio.flaskFill(e.phase, progress: progress);
      },
    );
    // 상전이 이벤트 → 결빙 crackle·증발 puff·반응 sizzle (LevelSession 패스스루, 관찰만 —
    // 결정성 무영향). 전이 결과 물질(materialTo)로 종류를 구분: ICE 결빙, STEAM 증발, STONE 반응.
    // (WATER로의 전이 = 녹음/응결은 전용 SFX 없음 → null.)
    _session.onPhaseChange = (materialFrom, materialTo, x, y) {
      final PhaseSfx? sfx = switch (materialTo) {
        _kIce => PhaseSfx.crackle,
        _kSteam => PhaseSfx.puff,
        _kStone => PhaseSfx.sizzle,
        _ => null,
      };
      if (sfx != null) widget.audio.phaseTransition(sfx);
    };
    _loop = GameLoop(onTick: () => _session.tick());
    _ticker = createTicker(_onFrame)..start();
    WidgetsBinding.instance.addObserver(this); // 앱 백그라운드 전환 감지.
    widget.audio.setBgmChapter(widget.entry.chapter); // 챕터 팔레트 BGM (기본 OFF).
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
    _exhaustTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.audio.stopAll(); // 화면 이탈 시 루프성 재생(앰비언트 등) 전부 정지 — 전역 잔존 방지.
    _ticker.dispose(); // 프레임 정지 먼저 — 이후 세션을 건드리지 않는다.
    _session.dispose(); // InkController(ChangeNotifier) 등 세션 소유 자원 해제 (감사 P2-2).
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
    // (그레인은 원샷이라 setAmbience 호출을 멈추면 수십~백 ms 내 자연 소멸 — 별도 정지 불필요.
    //  BGM은 일시정지 중에도 유지한다.)
    if (!_simRunning) return;

    _loop.advance(elapsed);
    _frameTick.value++;

    // 물질 앰비언트/파티클 그레인 — 활성 밀도로 짧은 그레인을 확률 발사 (샘플 스로틀, GDD 9.2).
    // 기본 OFF: 저역 웅웅거림("우웅") 실플레이 피드백 — 이벤트 SFX만 유지 (sound_tokens 참조).
    if (GrainPlay.ambientLayersDefaultEnabled &&
        ++_ambientFrame % GrainPlay.sampleEveryFrames == 0) {
      final d = _ambientDensities();
      widget.audio.setAmbience(
          particle: d.particle, water: d.water, steam: d.steam);
    }

    if (_session.isFailed) {
      _outcome.value = const _Outcome(_Phase.failed);
      widget.audio.fail();
    } else if (_session.isCleared) {
      final stars = _session.result.stars;
      _clearTicks = _session.game.tickCount; // 소요 시간 캡처(정지 후 값 고정).
      // 첫 클리어면 별점 설명을 1회 노출(이후 영속으로 숨김).
      _explainStars = widget.onboarding.markSeenOnce(OnboardingKey.firstClear);
      _outcome.value = _Outcome(_Phase.cleared, stars: stars);
      _recordResult(stars);
      // 클리어 스팅어가 BGM을 덕킹한다(GDD 9.2). 그레인은 시뮬 정지로 자연 소멸.
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
    _maybeScheduleExhaustNudge();
  }

  /// 모든 잉크를 소진했고 아직 미클리어면, 8초 뒤 재시작 넛지를 예약한다(1회).
  /// 잉크는 되돌아오지 않으므로 한 번 소진되면 재시작 전까지 조건이 유지된다.
  void _maybeScheduleExhaustNudge() {
    if (_exhaustScheduled || _exhaustNudge) return;
    final b = _session.ink.budget;
    final exhausted = b.totalInitial > 0 && b.totalRemaining == 0;
    if (!exhausted || _outcome.value.phase != _Phase.playing) return;
    _exhaustScheduled = true;
    _exhaustTimer = Timer(_exhaustDelay, () {
      if (!mounted) return;
      final stillExhausted = _session.ink.budget.totalRemaining == 0;
      if (stillExhausted && _outcome.value.phase == _Phase.playing) {
        setState(() => _exhaustNudge = true);
      }
    });
  }

  /// 활성 밀도 3종(0~1) — 파티클(동적 입자/액체/기체 총합)·물(WATER)·증기(STEAM).
  /// 그리드 1회 스캔. 파티클 그레인은 낙하·퇴적음, 물/증기는 물질 앰비언트(GDD 9.2 레이어).
  ({double particle, double water, double steam}) _ambientDensities() {
    final cells = _session.game.grid.cells;
    const water = 6; // Material.water.index
    const steam = 7; // Material.steam.index
    var dyn = 0, w = 0, s = 0;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == 0) continue;
      switch (propsOf(c).category) {
        case MaterialCategory.particle:
        case MaterialCategory.liquid:
        case MaterialCategory.gas:
          dyn++;
        case MaterialCategory.none:
        case MaterialCategory.staticSolid:
          break;
      }
      if (c == water) w++;
      if (c == steam) s++;
    }
    return (
      particle: (dyn / GrainPlay.densityRefCells).clamp(0.0, 1.0),
      water: (w / GrainPlay.ambientRefCells).clamp(0.0, 1.0),
      steam: (s / GrainPlay.ambientRefCells).clamp(0.0, 1.0),
    );
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
    // 잉크 소진 넛지 해제 (재시작으로 잉크 복원).
    _exhaustTimer?.cancel();
    _exhaustScheduled = false;
    _exhaustNudge = false;
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
                    painter: WorldPointsPainter(
                      cells: _session.game.grid.cells,
                      gridWidth: SimConstants.gridWidth,
                      gridHeight: SimConstants.gridHeight,
                      repaint: _frameTick,
                    ),
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
          // 상단 우측 스택: 버튼 행 → 초시계 → 잉크 팔레트(세로 컴팩트).
          Positioned(
            top: topPad + InkSpace.sm,
            right: InkSpace.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
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
                const SizedBox(height: InkSpace.sm),
                // 초시계 (시뮬 틱 기반 — 일시정지·백그라운드 자동 정지, 재시작 리셋).
                ValueListenableBuilder<int>(
                  valueListenable: _frameTick,
                  builder: (context, _, child) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: InkSpace.sm, vertical: InkSpace.xs),
                    decoration: BoxDecoration(
                      color: InkColor.black2.withValues(alpha: 0.85),
                      border: Border.all(color: InkColor.hairline),
                      borderRadius: BorderRadius.circular(InkSpace.radius),
                    ),
                    child: Semantics(
                      label: '경과 시간',
                      child: Text(
                        formatElapsed(_session.game.tickCount),
                        style: InkText.caption.copyWith(
                          color: InkColor.parchment,
                          fontFeatures: InkText.tabular,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: InkSpace.sm),
                InkPaletteBar(
                  controller: _session.ink,
                  vertical: true,
                  emphasizeCount: _gaugeEmphasize,
                  onSelect: () {
                    widget.settings.hapticSelection();
                    widget.audio.uiTap();
                  },
                ),
              ],
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
          // 잉크 소진 넛지 (P2) — 하단, 잉크 바 위. 재생 중일 때만.
          if (_exhaustNudge && !_paused &&
              _outcome.value.phase == _Phase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad + 118,
              child: Center(
                child: InkExhaustNudge(onRetry: _retry, reducedMotion: reduced),
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
                  onHome: _exit,
                  reducedMotion: reduced,
                  elapsedLabel: formatElapsed(_clearTicks),
                  onStarStamped: widget.settings.hapticLight,
                  // 첫 클리어에만 별점 설명 1줄 + 이번 판 사용량/임계.
                  starHelp: _explainStars ? OnboardingCopy.starExplain : null,
                  usageLine: clearUsageLine(
                      widget.entry.level, _session.ink.budget.totalUsed),
                );
              }
              if (o.phase == _Phase.failed) {
                return FailOverlay(
                    eyebrow: _eyebrow, onRetry: _retry, onHome: _exit);
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

/// 목표 용기를 **윗면 개방 U자 비커 실루엣**으로 그린다 (실플레이 피드백 — "여기에 받아라"의
/// 수집감). 상단 변 제거 + 좌우 립(주둥이) + 둥근 바닥 + 내부 수위선(채움 진행도). 카운트 숫자
/// 유지, 조건(물질 점·상태 글자·순수 !)은 립 위. 색은 InkColor 토큰, 두께는 [_wall].
class _FlaskHudPainter extends CustomPainter {
  final LevelSession session;
  final _FlaskLabelCache labels;
  _FlaskHudPainter(this.session, this.labels);

  static const double _wall = 2.0; // 벽 두께 (단일 소스)

  static String _stateChar(FlaskState s) => switch (s) {
        FlaskState.solid => '고',
        FlaskState.liquid => '액',
        FlaskState.gas => '기',
      };

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _wall
      ..strokeJoin = StrokeJoin.round
      ..color = InkColor.gold;

    final flasks = session.flasks.flasks;
    for (var i = 0; i < flasks.length; i++) {
      final flask = flasks[i];
      final s = flask.spec;
      final l = vp.offsetX + s.x * vp.scale;
      final t = vp.offsetY + s.y * vp.scale;
      final w = s.w * vp.scale.toDouble();
      final h = s.h * vp.scale.toDouble();
      final r = l + w;
      final b = t + h;

      final flare = (w * 0.12).clamp(2.0, 8.0);
      final lipDrop = (h * 0.12).clamp(3.0, 12.0);
      final cr = (math.min(w, h) * 0.22).clamp(2.0, 14.0);
      final innerTop = t + lipDrop;

      // 개방형 U 경로 (상단 변 없음, 좌우 립 벌어짐, 둥근 바닥).
      final beaker = Path()
        ..moveTo(l - flare, t)
        ..lineTo(l, innerTop)
        ..lineTo(l, b - cr)
        ..quadraticBezierTo(l, b, l + cr, b)
        ..lineTo(r - cr, b)
        ..quadraticBezierTo(r, b, r, b - cr)
        ..lineTo(r, innerTop)
        ..lineTo(r + flare, t);

      // 내부 수위(채움 진행도) — 비커 모양으로 클립해 둥근 바닥까지 채운다.
      final progress =
          s.goal > 0 ? (flask.count / s.goal).clamp(0.0, 1.0) : 0.0;
      if (progress > 0 && !flask.isFailed) {
        final waterY = b - progress * (b - innerTop);
        final fillColor = s.material != null
            ? Color(propsOf(s.material!.index).argb)
            : InkColor.gold;
        canvas.save();
        canvas.clipPath(beaker);
        canvas.drawRect(
          Rect.fromLTRB(l, waterY, r, b),
          Paint()..color = fillColor.withValues(alpha: 0.28),
        );
        canvas.drawLine(
          Offset(l, waterY),
          Offset(r, waterY),
          Paint()
            ..color = fillColor.withValues(alpha: 0.9)
            ..strokeWidth = 1.5,
        );
        canvas.restore();
      }

      canvas.drawPath(beaker, wall);

      // 립 위: 물질 점 + 카운트/목표 + 상태 글자(+ 순수 !).
      final label = flask.isFailed
          ? '✕'
          : '${flask.count}/${s.goal}'
              '${s.state != null ? ' ${_stateChar(s.state!)}' : ''}'
              '${s.pure ? ' !' : ''}';
      final tp = labels.painterFor(i, label);
      final labelY = t - flare - 14;
      var labelX = l;
      // 물질 점 (색으로 목표 물질 암시).
      if (s.material != null && !flask.isFailed) {
        final dotColor = Color(propsOf(s.material!.index).argb);
        canvas.drawCircle(
          Offset(l + 4, labelY + tp.height / 2),
          3,
          Paint()..color = dotColor,
        );
        labelX = l + 12;
      }
      tp.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(_FlaskHudPainter oldDelegate) => true;
}
