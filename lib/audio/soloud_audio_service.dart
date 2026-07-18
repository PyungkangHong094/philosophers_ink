/// flutter_soloud 절차 합성 오디오 구현 (GDD 9). 오디오 에셋 없이 파형 오실레이터로
/// 1차 SFX를 코드 생성한다. 초기화/재생 실패는 전부 삼켜 무음화 — 게임을 죽이지 않는다.
///
/// 각 이벤트는 파형 소스의 주파수를 세팅해 짧게 재생하고 볼륨을 페이드아웃(클릭 방지)한다.
/// 재생마다 ±detune 랜덤으로 반복감을 줄인다(GDD 9.2 변주 원칙). BGM은 에셋 확보 후 M5+.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../level/level_model.dart' show FlaskState;
import 'audio_service.dart';
import 'sound_tokens.dart';

class SoLoudAudioService implements AudioService {
  final SoLoud _soloud;
  final math.Random _rng = math.Random();

  bool _ready = false;
  bool _enabled = true;
  double _master = 0.8;

  // 파형 소스 — 재사용(이벤트마다 주파수만 바꿔 재생).
  AudioSource? _tri;
  AudioSource? _square;
  AudioSource? _saw;

  // 앰비언트 그레인 루프.
  AudioSource? _grain;
  SoundHandle? _grainHandle;

  SoLoudAudioService({SoLoud? engine}) : _soloud = engine ?? SoLoud.instance;

  @override
  Future<void> init() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
      }
      _tri = await _soloud.loadWaveform(WaveForm.triangle, false, 1, 0);
      _square = await _soloud.loadWaveform(WaveForm.fSquare, false, 1, 0);
      _saw = await _soloud.loadWaveform(WaveForm.fSaw, false, 1, 0);
      // 앰비언트 그레인은 기본 OFF(연속 드론 "지잉" 방지) — 켜질 때만 소스를 만든다.
      if (SfxSpec.ambientGrainEnabled) {
        _grain = await _soloud.loadWaveform(WaveForm.saw, true, 0.5, 0.4);
      }
      _ready = true;
    } catch (e) {
      // 미지원 플랫폼·헤드리스 테스트 등 — 무음화.
      _ready = false;
      if (kDebugMode) debugPrint('[audio] 초기화 실패, 무음: $e');
    }
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    try {
      stopAmbient();
      await _soloud.disposeAllSources();
    } catch (_) {}
    _ready = false;
  }

  @override
  void configure({required bool enabled, required double volume}) {
    _enabled = enabled;
    _master = volume.clamp(0.0, 1.0);
    if (!enabled) stopAmbient();
  }

  bool get _on => _ready && _enabled && _master > 0;

  /// ±detuneCents 랜덤 배수.
  double _detuned(double freq) {
    final cents =
        (_rng.nextDouble() * 2 - 1) * SfxSpec.detuneCents;
    return freq * math.pow(2, cents / 1200.0);
  }

  /// 단발 블립 — 소스 주파수 세팅 후 재생, 릴리스만큼 페이드아웃 + 정지 예약.
  void _blip(AudioSource? source, double freq, double vol, int ms,
      {double mix = 1.0, int delayMs = 0}) {
    if (!_on || source == null) return;
    void fire() {
      try {
        _soloud.setWaveformFreq(source, _detuned(freq));
        final v = (vol * _master * mix).clamp(0.0, 1.0);
        final h = _soloud.play(source, volume: v);
        final d = Duration(milliseconds: ms);
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

  void _arpeggio(AudioSource? source, List<double> freqs, double vol,
      int noteMs, int staggerMs) {
    for (var i = 0; i < freqs.length; i++) {
      _blip(source, freqs[i], vol, noteMs,
          mix: SfxMix.event, delayMs: i * staggerMs);
    }
  }

  @override
  void uiTap() =>
      _blip(_square, SfxSpec.uiTapFreq, SfxSpec.uiTapVol, SfxSpec.uiTapMs,
          mix: SfxMix.event);

  DateTime _lastStroke = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void stroke() {
    final now = DateTime.now();
    if (now.difference(_lastStroke).inMilliseconds <
        SfxSpec.strokeThrottleMs) {
      return;
    }
    _lastStroke = now;
    _blip(_tri, SfxSpec.strokeFreq, SfxSpec.strokeVol, SfxSpec.strokeMs,
        mix: SfxMix.event);
  }

  DateTime _lastFlask = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void flaskFill(FlaskState? phase) {
    // 입자가 빠르게 쏟아질 때 착수 이벤트가 초당 수십 회 → 블립 겹침 버즈. 스로틀로 틱화.
    final now = DateTime.now();
    if (now.difference(_lastFlask).inMilliseconds < SfxSpec.flaskThrottleMs) {
      return;
    }
    _lastFlask = now;
    final freq = switch (phase) {
      FlaskState.solid => SfxSpec.flaskSolidFreq,
      FlaskState.liquid => SfxSpec.flaskLiquidFreq,
      FlaskState.gas => SfxSpec.flaskGasFreq,
      null => SfxSpec.flaskBaseFreq,
    };
    _blip(_tri, freq, SfxSpec.flaskVol, SfxSpec.flaskMs, mix: SfxMix.event);
  }

  @override
  void clearStinger() => _arpeggio(_tri, SfxSpec.clearArp, SfxSpec.clearVol,
      SfxSpec.clearNoteMs, SfxSpec.clearStaggerMs);

  @override
  void operatioStinger() => _arpeggio(_square, SfxSpec.operatioArp,
      SfxSpec.operatioVol, SfxSpec.operatioNoteMs, SfxSpec.operatioStaggerMs);

  @override
  void fail() => _arpeggio(
      _saw, SfxSpec.failArp, SfxSpec.failVol, SfxSpec.failNoteMs,
      SfxSpec.failStaggerMs);

  @override
  void setAmbientDensity(double normalized) {
    if (!SfxSpec.ambientGrainEnabled) return; // 기본 OFF (드론 방지).
    if (!_on || _grain == null) return;
    // 샘플 스로틀은 호출부(PlayScreen)가 담당 — 여기선 받은 값을 즉시 반영.
    final target =
        (normalized.clamp(0.0, 1.0) * SfxSpec.grainMaxVol * _master *
                SfxMix.grain)
            .clamp(0.0, 1.0);
    try {
      if (_grainHandle == null) {
        final h = _soloud.play(_grain!, volume: 0, looping: true);
        _soloud.setWaveformFreq(_grain!, SfxSpec.grainFreq);
        _grainHandle = h;
      }
      _soloud.fadeVolume(_grainHandle!, target,
          const Duration(milliseconds: SfxSpec.grainRampMs));
    } catch (_) {}
  }

  @override
  void stopAmbient() {
    final h = _grainHandle;
    _grainHandle = null;
    if (h == null) return;
    try {
      _soloud.stop(h);
    } catch (_) {}
  }

  @override
  void stopAll() {
    // 현재 유일한 루프성 재생은 앰비언트 그레인. 원샷 SFX는 scheduleStop으로 자연 종료.
    // (향후 BGM 추가 시 여기서 함께 정지.)
    stopAmbient();
  }
}
