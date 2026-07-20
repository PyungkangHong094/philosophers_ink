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
import '../../level/level_model.dart' show FlaskState, HintStroke;
import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/onboarding.dart';
import '../../meta/progress.dart';
import '../../monetize/monetization.dart';
import '../../render/world_painter.dart';
import '../../sim/materials.dart';
import '../onboarding/onboarding_text.dart';
import '../onboarding/onboarding_widgets.dart';
import '../settings_controller.dart';
import '../tokens.dart';
import 'clear_overlay.dart';
import 'exhaust_nudge.dart';
import 'gimmick_overlay_painter.dart';
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

  /// 실패 사유 (phase == failed일 때만 의미). shell이 문구를 분기한다 (감사 Q1-2).
  final LevelFailure? failure;
  const _Outcome(this.phase, {this.stars = 0, this.failure});
}

class PlayScreen extends StatefulWidget {
  final LevelEntry entry;
  final GameProgress progress;
  final SettingsController settings;
  final AudioService audio;
  final OnboardingState onboarding;
  final Monetization monetization;

  /// "다음 레벨" 콜백. null이면 다음이 없거나 잠김 — 버튼 숨김.
  final VoidCallback? onNext;

  const PlayScreen({
    super.key,
    required this.entry,
    required this.progress,
    required this.settings,
    required this.audio,
    required this.onboarding,
    required this.monetization,
    this.onNext,
  });

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late LevelSession _session;
  late final GameLoop _loop;
  late final Ticker _ticker;

  final ValueNotifier<_Outcome> _outcome =
      ValueNotifier<_Outcome>(const _Outcome(_Phase.playing));
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  /// 남은 시간(초) — 카운트다운 HUD 전용 파생 notifier. 표시 초가 바뀔 때만 갱신해
  /// 60Hz 리빌드를 1Hz로 좁힌다 (감사 P3-1 + Q1-2).
  final ValueNotifier<int> _countdownSeconds = ValueNotifier<int>(0);
  int _lastShownSeconds = -1;

  /// 플라스크 상태(카운트·오염) 변화 시에만 플라스크 HUD를 repaint (감사 P2-1).
  final ValueNotifier<int> _flaskTick = ValueNotifier<int>(0);
  int _flaskSignature = 0;

  /// 임박 강조 임계(초). 이하로 남으면 카운트다운을 경고색으로 (골드 아님 — 희소성 보존).
  static const int _imminentSeconds = 10;

  /// 착수 햅틱 스로틀 — 연속 착수 시 과진동 방지 (오디오 flaskThrottle와 같은 취지).
  DateTime _lastSettleHaptic = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _settleHapticThrottleMs = 70;

  /// 플라스크 완성 펄스 컨트롤러 + 대상 인덱스 (Q1-3). 목표 도달 순간 1회 골드 링.
  late final AnimationController _pulseCtrl;
  int? _pulseFlaskIndex;

  /// 각 플라스크가 이미 완성됐는지 — 완성 "순간"을 1회만 감지하기 위한 래치.
  List<bool> _flaskWasComplete = const [];

  /// 이번 프레임의 reduced motion 값 (build에서 갱신). 완성 펄스 발화는 이 값을 존중한다
  /// — 콜백(틱 중)에서 context 없이도 설정+시스템 disableAnimations를 함께 반영.
  bool _reduced = false;

  bool _paused = false;
  bool _recorded = false;

  int? _activeStrokeId;
  (int, int)? _lastCell;
  Size _viewSize = Size.zero;
  int _ambientFrame = 0;

  /// 플라스크 라벨 TextPainter 캐시 — 라벨 문자열이 바뀔 때만 재생성 (감사 P3-2).
  final _FlaskLabelCache _flaskLabels = _FlaskLabelCache();

  /// 둥근 점 렌더의 물질별 좌표 버퍼 — 페인터가 재사용해 페인트당 할당 0 (감사 P1-1).
  final WorldPointBuffers _pointBuffers = WorldPointBuffers();

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

  // 힌트(리워드 광고) — 정답 스트로크 1개를 고스트 라인으로 (GDD 12).
  bool _hintVisible = false;
  bool _hintPending = false; // 광고 요청 중 중복 탭 방지.

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

  /// 힌트 버튼 노출 조건 (GDD 12): 정답 스트로크가 있고 작업(OPERATIO) 레벨이 아닐 때.
  /// hint_stroke null·빈 배열 또는 11배수 작업 레벨은 힌트 비활성.
  bool get _hintAvailable {
    if (isOperatioLevel(widget.entry.id)) return false;
    final s = widget.entry.level.meta.hintStroke;
    return s != null && s.isNotEmpty;
  }

  /// 힌트 요청 — 리워드 광고(스텁: 즉시 성공). 보상 시 고스트 라인 노출. 미준비면 안내.
  Future<void> _requestHint() async {
    if (_hintVisible || _hintPending) return;
    _hintPending = true;
    final ok = await widget.monetization.requestHint();
    _hintPending = false;
    if (!mounted) return;
    if (ok) {
      setState(() => _hintVisible = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('힌트를 지금 불러올 수 없어요'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // 플라스크 착수 이벤트 → 착수 틱(카운트업 동기, GDD 9.2). 상별 피치 + 채움 진행도로 램프.
    _session = LevelSession(
      widget.entry.level,
      onSettle: (e) {
        final flasks = _session.flasks.flasks;
        final inRange = e.flaskIndex >= 0 && e.flaskIndex < flasks.length;
        final goal = inRange ? flasks[e.flaskIndex].spec.goal : 0;
        final count = inRange ? flasks[e.flaskIndex].count : 0;
        final progress = goal > 0 ? count / goal : 0.0;
        widget.audio.flaskFill(e.phase, progress: progress);
        // 착수 햅틱 (Q1-3) — 스로틀. 설정 오프 시 무진동(hapticLight가 게이트).
        final now = DateTime.now();
        if (now.difference(_lastSettleHaptic).inMilliseconds >=
            _settleHapticThrottleMs) {
          _lastSettleHaptic = now;
          widget.settings.hapticLight();
        }
        // 플라스크 완성 "순간" 감지 → 완성 펄스 + medium 햅틱 (1회, Q1-3).
        if (inRange &&
            e.flaskIndex < _flaskWasComplete.length &&
            flasks[e.flaskIndex].isComplete &&
            !_flaskWasComplete[e.flaskIndex]) {
          _flaskWasComplete[e.flaskIndex] = true;
          _onFlaskCompleted(e.flaskIndex);
        }
      },
    );
    _flaskWasComplete = List<bool>.filled(_session.flasks.flasks.length, false);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 460));
    _lastShownSeconds =
        (_session.remainingTicks / SimConstants.tickRateHz).ceil();
    _countdownSeconds.value = _lastShownSeconds;
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
    _flaskTick.dispose();
    _countdownSeconds.dispose();
    _pulseCtrl.dispose();
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

    // 플라스크 HUD는 카운트·오염이 바뀔 때만 repaint (감사 P2-1). 시그니처 비교.
    final sig = _flaskSignatureNow();
    if (sig != _flaskSignature) {
      _flaskSignature = sig;
      _flaskTick.value++;
    }

    // 카운트다운 1Hz 갱신 (감사 P3-1 + Q1-2) — 표시 초가 바뀔 때만.
    final secs = (_session.remainingTicks / SimConstants.tickRateHz).ceil();
    if (secs != _lastShownSeconds) {
      _lastShownSeconds = secs;
      _countdownSeconds.value = secs;
    }

    // 물질 앰비언트/파티클 그레인 — 활성 밀도로 짧은 그레인을 확률 발사 (샘플 스로틀, GDD 9.2).
    // 기본 OFF: 저역 웅웅거림("우웅") 실플레이 피드백 — 이벤트 SFX만 유지 (sound_tokens 참조).
    if (GrainPlay.ambientLayersDefaultEnabled &&
        ++_ambientFrame % GrainPlay.sampleEveryFrames == 0) {
      final d = _ambientDensities();
      widget.audio.setAmbience(
          particle: d.particle, water: d.water, steam: d.steam);
    }

    if (_session.isFailed) {
      // 실패 사유(오염/타임아웃)를 실어 shell이 문구를 분기한다 (감사 Q1-2).
      _outcome.value =
          _Outcome(_Phase.failed, failure: _session.failureReason);
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

  /// 플라스크 HUD repaint 트리거용 시그니처 — 카운트·오염이 바뀔 때만 값이 변한다 (감사 P2-1).
  /// 채움 게이지는 count로 실시간 반영되고, 매 프레임 무조건 repaint(구 shouldRepaint=>true)는
  /// 제거된다. 순수 정수 폴드라 할당 0.
  int _flaskSignatureNow() {
    var h = 0;
    for (final f in _session.flasks.flasks) {
      h = 0x1fffffff & (h * 31 + f.count);
      h = 0x1fffffff & (h * 31 + (f.isFailed ? 1 : 0));
    }
    return h;
  }

  /// 플라스크 완성 순간 1회 (Q1-3): medium 햅틱 + 완성 펄스(골드 링). reduced motion이면
  /// 펄스는 생략하고 햅틱만(설정 오프 시 hapticMedium 내부 게이트로 무진동).
  void _onFlaskCompleted(int index) {
    widget.settings.hapticMedium();
    if (_reduced) return;
    _pulseFlaskIndex = index;
    _pulseCtrl.forward(from: 0);
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
    _hintVisible = false; // 재시작 시 고스트 힌트 숨김.
    // 완성 래치·펄스 초기화 — 재시작 후에도 완성 순간 햅틱/펄스가 다시 발화하도록 (Q1-3).
    _flaskWasComplete = List<bool>.filled(_session.flasks.flasks.length, false);
    _pulseCtrl.reset();
    _pulseFlaskIndex = null;
    // _flaskSignature는 그대로 둔다 — 리셋된 카운트(0)와 값이 달라 다음 틱에 _flaskTick이
    // 발화해 플라스크 HUD가 0/목표로 즉시 갱신된다.
    // 카운트다운은 즉시 제한시간으로 복귀 — 다음 틱을 기다리지 않고 동기 리셋(initState와 동일).
    _lastShownSeconds =
        (_session.remainingTicks / SimConstants.tickRateHz).ceil();
    _countdownSeconds.value = _lastShownSeconds;
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
    // 완성 펄스는 틱 콜백(context 없음)에서 발화하므로 이번 프레임 값을 캐시한다.
    _reduced = reduced;

    return Scaffold(
      backgroundColor: Color(widget.entry.level.background),
      // 자식이 전부 Positioned라 fit 미지정 시 느슨한 제약에서 Stack이 0×0으로
      // 붕괴한다(실기기 블랙스크린의 원인). expand로 화면 크기를 강제한다.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 기믹·방출구 정적 표식 (배경과 물질 사이, GDD 6·8.1 / 감사 Q1-1). 포탈·변성 게이트·
          // 온도 존·방출구는 sim에서 비물질 셀 집합이라 화면에 안 그려져 플레이어가 순간이동/
          // 상전이/방출을 못 읽는다 — 레벨 좌표만으로 정적 1회 표식을 그린다. sim 상태를
          // 구독하지 않아 결정성·성능 무영향, 레벨 불변이라 RepaintBoundary로 재래스터 차단.
          // 골드 미사용(셸 규칙 무관 인게임 채도 — 배경 명도 대비 헤일로로 식별 보장).
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: GimmickOverlayPainter(widget.entry.level),
                ),
              ),
            ),
          ),
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
                      buffers: _pointBuffers,
                      repaint: _frameTick,
                    ),
                  ),
                );
              },
            ),
          ),
          // 플라스크 목표 오버레이. 카운트·오염이 바뀔 때만 repaint (감사 P2-1) — 매 프레임
          // 아님. _flaskTick(시그니처 변화 시 1틱)이 repaint를 구동하고 RepaintBoundary로
          // 분리해 이웃 레이어 리페인트에 휩쓸리지 않는다.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FlaskHudPainter(
                      _session, _flaskLabels, repaint: _flaskTick),
                ),
              ),
            ),
          ),
          // 플라스크 완성 펄스 — 목표 도달 순간 1회 골드 링(달성, 셸 원칙2). pulse 애니메이션
          // 진행 중에만 repaint(reduced motion이면 발화 안 함). 비커 위에 얹는다.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FlaskPulsePainter(
                      _session, _pulseCtrl, () => _pulseFlaskIndex),
                ),
              ),
            ),
          ),
          // 힌트 고스트 라인 (정답 스트로크 1개, GDD 12). 골드 아닌 중립 parchment —
          // 힌트는 성취가 아니므로 골드 희소성 예외 아님. 리워드 광고 성공 시에만 노출.
          if (_hintVisible && _hintAvailable)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HintGhostPainter(
                    widget.entry.level.meta.hintStroke!,
                  ),
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
                    // 힌트(리워드 광고) — 정답 스트로크가 있고 작업 레벨이 아닐 때만.
                    if (_hintAvailable && !_hintVisible) ...[
                      _HudIconButton(
                        icon: Icons.lightbulb_outline,
                        label: '힌트',
                        onTap: _requestHint,
                      ),
                      const SizedBox(width: InkSpace.sm),
                    ],
                    _HudIconButton(
                      icon: Icons.pause,
                      label: '일시정지',
                      onTap: () => setState(() => _paused = true),
                    ),
                  ],
                ),
                const SizedBox(height: InkSpace.sm),
                // 남은 시간 카운트다운 (시뮬 틱 기반 — 일시정지·백그라운드 자동 정지, 재시작 리셋).
                // 1Hz 갱신(감사 P3-1): 표시 초가 바뀔 때만 리빌드. ≤10초는 경고색으로 임박을
                // 알린다 (골드 아님 — 골드 희소성 보존, InkColor.warn 주홍).
                ValueListenableBuilder<int>(
                  valueListenable: _countdownSeconds,
                  builder: (context, secs, child) {
                    final imminent = secs <= _imminentSeconds;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: InkSpace.sm, vertical: InkSpace.xs),
                      decoration: BoxDecoration(
                        color: InkColor.black2.withValues(alpha: 0.85),
                        border: Border.all(
                            color:
                                imminent ? InkColor.warn : InkColor.hairline),
                        borderRadius: BorderRadius.circular(InkSpace.radius),
                      ),
                      child: Semantics(
                        label: '남은 시간',
                        child: Text(
                          formatClock(secs),
                          style: InkText.caption.copyWith(
                            color:
                                imminent ? InkColor.warn : InkColor.parchment,
                            fontFeatures: InkText.tabular,
                          ),
                        ),
                      ),
                    );
                  },
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
                    eyebrow: _eyebrow,
                    // 사유 유실 시 오염으로 폴백(순수 위반이 기본 실패 모드).
                    failure: o.failure ?? LevelFailure.contamination,
                    onRetry: _retry,
                    onHome: _exit);
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
              // 힌트가 아직 안 뜬 경우에만 일시정지에서도 요청 가능(계속 + 힌트).
              onHint: (_hintAvailable && !_hintVisible)
                  ? () {
                      setState(() => _paused = false);
                      _requestHint();
                    }
                  : null,
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

/// 힌트 고스트 라인 — 정답 힌트 스트로크(그리드 선분들)를 화면 좌표로 매핑해 반투명
/// parchment 선으로 그린다 (GDD 12 리워드 힌트). 각 [HintStroke]는 독립 선분
/// (x0,y0)-(x1,y1). 셀 중심 기준, 두께는 셀 크기 비례.
/// 골드 아님 — 힌트는 성취가 아니므로 중립색으로 골드 희소성을 지킨다.
class _HintGhostPainter extends CustomPainter {
  final List<HintStroke> strokes;
  _HintGhostPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    Offset toScreen(int x, int y) => Offset(
          vp.offsetX + (x + 0.5) * vp.scale,
          vp.offsetY + (y + 0.5) * vp.scale,
        );
    final path = Path();
    for (final s in strokes) {
      final a = toScreen(s.x0, s.y0);
      final b = toScreen(s.x1, s.y1);
      path.moveTo(a.dx, a.dy);
      path.lineTo(b.dx, b.dy);
    }
    // 소프트 글로우 → 코어 라인 2패스 (고스트 느낌).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (vp.scale * 1.6).clamp(3.0, 8.0)
        ..color = InkColor.parchment.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (vp.scale * 0.8).clamp(1.5, 4.0)
        ..color = InkColor.parchment.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_HintGhostPainter old) => old.strokes != strokes;
}

/// 목표 용기를 **윗면 개방 U자 비커 실루엣**으로 그린다 (실플레이 피드백 — "여기에 받아라"의
/// 수집감). 상단 변 제거 + 좌우 립(주둥이) + 둥근 바닥 + 내부 수위선(채움 진행도). 카운트 숫자
/// 유지, 조건(물질 점·상태 글자·순수 !)은 립 위. 색은 InkColor 토큰, 두께는 [_wall].
class _FlaskHudPainter extends CustomPainter {
  final LevelSession session;
  final _FlaskLabelCache labels;
  _FlaskHudPainter(this.session, this.labels, {required Listenable repaint})
      : super(repaint: repaint);

  static const double _wall = 2.0; // 벽 두께 (단일 소스)

  // 정적 Paint 재사용 — paint당 신규 할당 제거 (감사 P2-1). 색 가변인 것은 draw 직전 ..color.
  // 페인트는 UI 스레드 단일 실행이라 인스턴스 공유·변이가 안전하다.
  static final Paint _wallPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _wall
    ..strokeJoin = StrokeJoin.round
    ..color = InkColor.gold;
  static final Paint _fillPaint = Paint();
  static final Paint _waterLinePaint = Paint()..strokeWidth = 1.5;
  static final Paint _dotPaint = Paint();

  static String _stateChar(FlaskState s) => switch (s) {
        FlaskState.solid => '고',
        FlaskState.liquid => '액',
        FlaskState.gas => '기',
      };

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);

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
          _fillPaint..color = fillColor.withValues(alpha: 0.28),
        );
        canvas.drawLine(
          Offset(l, waterY),
          Offset(r, waterY),
          _waterLinePaint..color = fillColor.withValues(alpha: 0.9),
        );
        canvas.restore();
      }

      canvas.drawPath(beaker, _wallPaint);

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
          _dotPaint..color = dotColor,
        );
        labelX = l + 12;
      }
      tp.paint(canvas, Offset(labelX, labelY));
    }
  }

  // repaint는 _flaskTick(카운트·오염 시그니처 변화)이 구동한다 (감사 P2-1). 위젯이 새
  // 페인터로 재생성되는 경우(setState)만 여기서 판정 — 세션 인스턴스는 화면 생애 동안
  // 불변이라 통상 false. 매 프레임 repaint하던 구 shouldRepaint=>true를 대체한다.
  @override
  bool shouldRepaint(_FlaskHudPainter old) =>
      old.session != session || old.labels != labels;
}

/// 플라스크 완성 펄스 (Q1-3) — 완성 순간 대상 비커를 감싸는 골드 링이 1.0→1.35 확장하며
/// 페이드아웃. 달성 = 골드(셸 원칙2, 인게임 HUD의 승인된 골드 사용). [pulse]가 idle(값 0/1)이면
/// 아무것도 그리지 않아 상시 비용 0 — 애니메이션 중에만 repaint([pulse]가 구동).
class _FlaskPulsePainter extends CustomPainter {
  final LevelSession session;
  final Animation<double> pulse;
  final int? Function() indexOf;
  _FlaskPulsePainter(this.session, this.pulse, this.indexOf)
      : super(repaint: pulse);

  static final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final t = pulse.value;
    if (t <= 0 || t >= 1) return; // idle — 그릴 것 없음.
    final idx = indexOf();
    final flasks = session.flasks.flasks;
    if (idx == null || idx < 0 || idx >= flasks.length) return;
    final s = flasks[idx].spec;
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    final rect = Rect.fromLTWH(
      vp.offsetX + s.x * vp.scale,
      vp.offsetY + s.y * vp.scale,
      s.w * vp.scale.toDouble(),
      s.h * vp.scale.toDouble(),
    );
    final grow = 1.0 + 0.35 * Curves.easeOut.transform(t); // 확장 오버슛.
    final ring = Rect.fromCenter(
      center: rect.center,
      width: rect.width * grow,
      height: rect.height * grow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(ring, const Radius.circular(4)),
      _ring..color = InkColor.goldHi.withValues(alpha: (1.0 - t) * 0.9),
    );
  }

  @override
  bool shouldRepaint(_FlaskPulsePainter old) => true;
}
