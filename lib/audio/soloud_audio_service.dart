/// flutter_soloud 절차 합성 오디오 구현 (GDD 9) — 정밀 재설계.
///
/// 톤 SFX는 파형 오실레이터 풀(폴리포니, 겹침 글리치 방지)로, 노이즈 SFX(결빙/증발/반응/
/// 파티클 그레인/물·증기)는 코드 생성한 짧은 PCM 그레인(wav.dart → loadMem)으로 만든다.
/// **모든 SFX·그레인은 짧은 원샷** — 연속 루프는 BGM(기본 OFF)뿐이라 "지잉" 드론 불가.
/// 재생마다 주파수·볼륨·길이 지터 + 노이즈 변주 3~5개 무작위 선택(GDD 9.2). 초기화/재생
/// 실패는 전부 삼켜 무음화한다.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../level/level_model.dart' show FlaskState;
import 'audio_service.dart';
import 'sound_tokens.dart';
import 'wav.dart';

class SoLoudAudioService implements AudioService {
  final SoLoud _soloud;
  final math.Random _rng = math.Random();

  bool _ready = false;
  bool _enabled = true;
  double _master = 0.8;
  bool _bgmEnabled = BgmSpec.defaultEnabled;

  // 톤 파형 소스 풀 (폴리포니 — 겹치는 음이 같은 소스의 주파수를 덮어쓰지 않게).
  final List<AudioSource> _tri = [];
  final List<AudioSource> _square = [];
  final List<AudioSource> _saw = [];
  int _triRr = 0, _sqRr = 0, _sawRr = 0;

  // 노이즈 그레인 소스 (변주 리스트).
  final List<AudioSource> _crackle = [];
  final List<AudioSource> _puff = [];
  final List<AudioSource> _sizzle = [];
  final List<AudioSource> _particle = [];
  final List<AudioSource> _water = [];
  final List<AudioSource> _steam = [];

  // BGM 패드 (챕터당 화음 보이스, 루프).
  final List<AudioSource> _padVoices = [];
  final List<SoundHandle> _padHandles = [];
  int _bgmChapter = 0;

  SoLoudAudioService({SoLoud? engine}) : _soloud = engine ?? SoLoud.instance;

  @override
  Future<void> init() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
      }
      // 톤 풀.
      for (var i = 0; i < 4; i++) {
        _tri.add(await _soloud.loadWaveform(WaveForm.triangle, false, 1, 0));
      }
      for (var i = 0; i < 3; i++) {
        _square.add(await _soloud.loadWaveform(WaveForm.fSquare, false, 1, 0));
      }
      for (var i = 0; i < 2; i++) {
        _saw.add(await _soloud.loadWaveform(WaveForm.fSaw, false, 1, 0));
      }
      // 노이즈 그레인 — 코드 생성 WAV loadMem.
      await _loadGrains('crackle', GrainKit.crackle, _crackle);
      await _loadGrains('puff', GrainKit.puff, _puff);
      await _loadGrains('sizzle', GrainKit.sizzle, _sizzle);
      await _loadGrains('particle', GrainKit.particle, _particle);
      await _loadGrains('water', GrainKit.water, _water);
      await _loadGrains('steam', GrainKit.steam, _steam);
      // BGM 패드 보이스 (화음 수만큼).
      for (var i = 0; i < BgmSpec.chordSemitones.length; i++) {
        _padVoices.add(await _soloud.loadWaveform(WaveForm.sin, false, 1, 0));
      }
      _ready = true;
    } catch (e) {
      _ready = false;
      if (kDebugMode) debugPrint('[audio] 초기화 실패, 무음: $e');
    }
  }

  Future<void> _loadGrains(
      String tag, List<GrainSpec> specs, List<AudioSource> out) async {
    for (var i = 0; i < specs.length; i++) {
      out.add(await _soloud.loadMem('grain_${tag}_$i', grainWav(specs[i])));
    }
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    try {
      _stopBgm();
      await _soloud.disposeAllSources();
    } catch (_) {}
    _ready = false;
  }

  @override
  void configure({
    required bool enabled,
    required double volume,
    required bool bgmEnabled,
  }) {
    _enabled = enabled;
    _master = volume.clamp(0.0, 1.0);
    final bgmWas = _bgmEnabled;
    _bgmEnabled = bgmEnabled;
    if (!enabled || !bgmEnabled) {
      _stopBgm();
    } else if (enabled && bgmEnabled && !bgmWas && _bgmChapter > 0) {
      _startBgm(_bgmChapter); // 토글 켜짐 → 재개.
    }
  }

  bool get _on => _ready && _enabled && _master > 0;

  double _detune(double freq) {
    final cents = (_rng.nextDouble() * 2 - 1) * SfxVary.freqCents;
    return freq * math.pow(2, cents / 1200.0);
  }

  int _jitterMs(int ms) =>
      (ms * (1 + (_rng.nextDouble() * 2 - 1) * SfxVary.len)).round().clamp(4, 4000);

  double _jitterVol(double v) =>
      v * (1 + (_rng.nextDouble() * 2 - 1) * SfxVary.vol);

  AudioSource _next(List<AudioSource> pool, int rr) => pool[rr % pool.length];

  /// 톤 블립 — 풀에서 라운드로빈 소스를 골라 주파수·볼륨·길이를 지터해 재생.
  void _tone(List<AudioSource> pool, int Function() rrGet, void Function() rrInc,
      double freq, double vol, int ms,
      {double mix = 1.0, int delayMs = 0, bool jitter = true}) {
    if (!_on || pool.isEmpty) return;
    final src = _next(pool, rrGet());
    rrInc();
    final f = jitter ? _detune(freq) : freq;
    final v = ((jitter ? _jitterVol(vol) : vol) * _master * mix).clamp(0.0, 1.0);
    final d = Duration(milliseconds: jitter ? _jitterMs(ms) : ms);
    void fire() {
      try {
        _soloud.setWaveformFreq(src, f);
        final h = _soloud.play(src, volume: v);
        _soloud.fadeVolume(h, 0, d);
        _soloud.scheduleStop(h, d);
      } catch (_) {}
    }

    if (delayMs <= 0) {
      fire();
    } else {
      Future<void>.delayed(Duration(milliseconds: delayMs), fire);
    }
  }

  void _triTone(double freq, double vol, int ms,
          {double mix = 1.0, int delayMs = 0}) =>
      _tone(_tri, () => _triRr, () => _triRr++, freq, vol, ms,
          mix: mix, delayMs: delayMs);
  void _sqTone(double freq, double vol, int ms,
          {double mix = 1.0, int delayMs = 0}) =>
      _tone(_square, () => _sqRr, () => _sqRr++, freq, vol, ms,
          mix: mix, delayMs: delayMs);
  void _sawTone(double freq, double vol, int ms,
          {double mix = 1.0, int delayMs = 0}) =>
      _tone(_saw, () => _sawRr, () => _sawRr++, freq, vol, ms,
          mix: mix, delayMs: delayMs);

  /// 노이즈 그레인 원샷 — 변주 무작위 선택, 유한 길이라 자동 종료. [speed]로 피치 변조.
  void _grain(List<AudioSource> variants, double vol,
      {double mix = 1.0, double speed = 1.0}) {
    if (!_on || variants.isEmpty) return;
    final src = variants[_rng.nextInt(variants.length)];
    final v = (vol * _master * mix).clamp(0.0, 1.0);
    try {
      final h = _soloud.play(src, volume: v);
      if (speed != 1.0) _soloud.setRelativePlaySpeed(h, speed);
    } catch (_) {}
  }

  // ---- 이벤트 SFX ----

  @override
  void uiTap() {
    _sqTone(SfxSpec.uiTapFreq, SfxSpec.uiTapVol, SfxSpec.uiTapMs,
        mix: SfxMix.event);
    // 어택 반짝 배음 층 (game-audio 레이어링).
    _triTone(SfxSpec.uiTapFreq * SfxSpec.uiTapHarmonic,
        SfxSpec.uiTapVol * SfxSpec.uiTapHarmonicMix, SfxSpec.uiTapMs,
        mix: SfxMix.event);
  }

  DateTime _lastStroke = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void stroke() {
    final now = DateTime.now();
    if (now.difference(_lastStroke).inMilliseconds <
        SfxSpec.strokeThrottleMs) {
      return;
    }
    _lastStroke = now;
    _triTone(SfxSpec.strokeFreq, SfxSpec.strokeVol, SfxSpec.strokeMs,
        mix: SfxMix.event);
  }

  DateTime _lastFlask = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void flaskFill(FlaskState? phase, {double progress = 0}) {
    final now = DateTime.now();
    if (now.difference(_lastFlask).inMilliseconds < SfxSpec.flaskThrottleMs) {
      return;
    }
    _lastFlask = now;
    final base = switch (phase) {
      FlaskState.solid => SfxSpec.flaskSolidFreq,
      FlaskState.liquid => SfxSpec.flaskLiquidFreq,
      FlaskState.gas => SfxSpec.flaskGasFreq,
      null => SfxSpec.flaskBaseFreq,
    };
    // 카운트업 동기: 채움 진행도에 따라 피치 상승 (만족 커브, GDD 9.2 최우선).
    final ramp = math.pow(
        2, progress.clamp(0.0, 1.0) * SfxSpec.flaskRampSemitones / 12.0);
    _triTone(base * ramp, SfxSpec.flaskVol, SfxSpec.flaskMs, mix: SfxMix.event);
  }

  void _arp(void Function(double, double, int, {double mix, int delayMs}) voice,
      List<double> freqs, double vol, int noteMs, int stagger) {
    for (var i = 0; i < freqs.length; i++) {
      voice(freqs[i], vol, noteMs, mix: SfxMix.event, delayMs: i * stagger);
    }
  }

  @override
  void clearStinger() {
    _arp(_triTone, SfxSpec.clearArp, SfxSpec.clearVol, SfxSpec.clearNoteMs,
        SfxSpec.clearStaggerMs);
    _duckBgm();
  }

  @override
  void operatioStinger() {
    _arp(_sqTone, SfxSpec.operatioArp, SfxSpec.operatioVol,
        SfxSpec.operatioNoteMs, SfxSpec.operatioStaggerMs);
    _duckBgm();
  }

  @override
  void fail() => _arp(_sawTone, SfxSpec.failArp, SfxSpec.failVol,
      SfxSpec.failNoteMs, SfxSpec.failStaggerMs);

  // ---- 상전이 SFX (위치·밀도 스로틀) ----

  DateTime _phaseWindowStart = DateTime.fromMillisecondsSinceEpoch(0);
  int _phaseWindowCount = 0;

  @override
  void phaseTransition(PhaseSfx kind) {
    if (!_on) return;
    final now = DateTime.now();
    if (now.difference(_phaseWindowStart).inMilliseconds >=
        GrainPlay.phaseWindowMs) {
      _phaseWindowStart = now;
      _phaseWindowCount = 0;
    }
    if (_phaseWindowCount >= GrainPlay.phaseMaxPerWindow) return; // 초과분 생략(버즈 방지).
    // 윈도 내 후속 이벤트는 볼륨을 약간 가산(밀도감).
    final densityBoost = 1 + 0.15 * _phaseWindowCount;
    _phaseWindowCount++;
    switch (kind) {
      case PhaseSfx.crackle:
        _grain(_crackle, GrainPlay.crackleVol * densityBoost, mix: SfxMix.phase);
      case PhaseSfx.puff:
        _grain(_puff, GrainPlay.puffVol * densityBoost, mix: SfxMix.phase);
      case PhaseSfx.sizzle:
        _grain(_sizzle, GrainPlay.sizzleVol * densityBoost, mix: SfxMix.phase);
    }
  }

  // ---- 지속 레이어 (그레인·앰비언트) ----

  @override
  void setAmbience({
    required double particle,
    required double water,
    required double steam,
  }) {
    if (!_on) return;
    _fireGrains(_particle, particle, GrainPlay.grainDensityToCount,
        GrainPlay.grainMaxPerSample, GrainPlay.grainVol, SfxMix.grain,
        pitch: true);
    _fireGrains(_water, water, GrainPlay.ambientDensityToCount,
        GrainPlay.ambientMaxPerSample, GrainPlay.waterVol, SfxMix.ambient);
    _fireGrains(_steam, steam, GrainPlay.ambientDensityToCount,
        GrainPlay.ambientMaxPerSample, GrainPlay.steamVol, SfxMix.ambient);
  }

  void _fireGrains(List<AudioSource> variants, double density, double toCount,
      int maxCount, double vol, double mix,
      {bool pitch = false}) {
    if (density <= 0) return;
    final count = (density * toCount).floor().clamp(0, maxCount);
    for (var i = 0; i < count; i++) {
      // 밀도 비례 볼륨 + (옵션) 피치.
      final speed = pitch
          ? GrainPlay.grainSpeedMin +
              (GrainPlay.grainSpeedMax - GrainPlay.grainSpeedMin) *
                  density.clamp(0.0, 1.0)
          : 1.0;
      _grain(variants, vol * (0.6 + 0.4 * density.clamp(0.0, 1.0)),
          mix: mix, speed: speed);
    }
  }

  // ---- BGM (기본 OFF, 정적 패드 — 미검증 품질) ----

  @override
  void setBgmChapter(int chapter) {
    _bgmChapter = chapter;
    if (chapter <= 0) {
      _stopBgm();
      return;
    }
    if (_on && _bgmEnabled) _startBgm(chapter);
  }

  void _startBgm(int chapter) {
    if (!_on || !_bgmEnabled || _padVoices.isEmpty) return;
    _stopBgm();
    final root =
        BgmSpec.chapterRoot[(chapter - 1).clamp(0, BgmSpec.chapterRoot.length - 1)];
    try {
      for (var i = 0; i < _padVoices.length; i++) {
        final semis = BgmSpec.chordSemitones[i];
        final freq = root * math.pow(2, semis / 12.0);
        _soloud.setWaveformFreq(_padVoices[i], freq.toDouble());
        final v = (BgmSpec.padVol * SfxMix.bgm * _master).clamp(0.0, 1.0);
        final h = _soloud.play(_padVoices[i], volume: 0, looping: true);
        _soloud.fadeVolume(h, v, const Duration(milliseconds: 800));
        _padHandles.add(h);
      }
    } catch (_) {}
  }

  void _stopBgm() {
    for (final h in _padHandles) {
      try {
        _soloud.stop(h);
      } catch (_) {}
    }
    _padHandles.clear();
  }

  void _duckBgm() {
    if (_padHandles.isEmpty) return;
    final v = (BgmSpec.padVol * SfxMix.bgm * _master).clamp(0.0, 1.0);
    final ducked = v * BgmSpec.duckFactor;
    try {
      for (final h in _padHandles) {
        _soloud.fadeVolume(h, ducked, const Duration(milliseconds: 120));
      }
      Future<void>.delayed(const Duration(milliseconds: BgmSpec.duckMs), () {
        for (final h in _padHandles) {
          try {
            _soloud.fadeVolume(h, v, const Duration(milliseconds: 300));
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  @override
  void stopAmbient() => _stopBgm(); // 그레인은 원샷 자동 종료; 루프는 BGM뿐.

  @override
  void stopAll() => _stopBgm();
}
