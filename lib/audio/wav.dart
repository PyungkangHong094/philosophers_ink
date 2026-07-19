/// 절차 노이즈 그레인 합성 (GDD 9.1 파티클 ASMR). 순수 Dart — flutter 미의존, 단위 테스트 대상.
///
/// flutter_soloud의 파형 오실레이터에는 노이즈가 없어, 결빙 crackle·증발 puff·파티클 그레인·
/// 물/증기 앰비언트를 위해 16-bit PCM WAV 버퍼를 코드로 생성한다(soloud loadMem가 디코드).
/// 모든 버퍼는 짧다(수십~백 ms) — 연속 루프가 아니라 원샷 그레인이라 "지잉" 드론이 불가능하다.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 표준 샘플레이트.
const int kSampleRate = 44100;

/// 그레인 성형 스펙 — 노이즈에 필터·엔벨로프를 얹어 질감을 만든다.
class GrainSpec {
  final int ms; // 길이
  final int seed; // 결정적 변주
  /// 로우패스 계수 0~1 (작을수록 어둡다). 1이면 무필터.
  final double lowpass;
  /// 하이패스 계수 0~1 (클수록 밝은 히스). 0이면 무필터.
  final double highpass;
  /// 어택 비율(전체 길이 대비 0~1) — 페이드인.
  final double attack;
  /// 감쇠 지수(클수록 빨리 사라짐).
  final double decay;
  /// 진폭 워블 깊이 0~1 (물 흐름 등). 0이면 없음.
  final double wobble;
  /// 워블 주파수(Hz).
  final double wobbleHz;
  /// 톤 성분 주파수(Hz). 0이면 순수 노이즈(crackle의 미세 핑 등에 사용).
  final double toneHz;
  /// 톤 성분 믹스 0~1.
  final double toneMix;

  const GrainSpec({
    required this.ms,
    this.seed = 0,
    this.lowpass = 1.0,
    this.highpass = 0.0,
    this.attack = 0.02,
    this.decay = 6.0,
    this.wobble = 0.0,
    this.wobbleHz = 8.0,
    this.toneHz = 0.0,
    this.toneMix = 0.0,
  });
}

/// [spec]대로 노이즈 그레인 샘플(-1~1)을 생성한다. 결정적(seed 고정).
List<double> synthGrain(GrainSpec spec, {int sampleRate = kSampleRate}) {
  final n = (sampleRate * spec.ms / 1000).round().clamp(1, 1 << 20);
  final rng = math.Random(spec.seed ^ 0x9E3779B9);
  final out = List<double>.filled(n, 0.0);

  // 1) 화이트 노이즈.
  for (var i = 0; i < n; i++) {
    out[i] = rng.nextDouble() * 2 - 1;
  }
  // 2) 로우패스 (1극) — 어둡게.
  if (spec.lowpass < 1.0) {
    var y = 0.0;
    final a = spec.lowpass.clamp(0.001, 1.0);
    for (var i = 0; i < n; i++) {
      y += a * (out[i] - y);
      out[i] = y;
    }
  }
  // 3) 하이패스 (1극) — 히스.
  if (spec.highpass > 0.0) {
    final a = spec.highpass.clamp(0.0, 0.999);
    var prevX = 0.0;
    var prevY = 0.0;
    for (var i = 0; i < n; i++) {
      final x = out[i];
      final y = a * (prevY + x - prevX);
      prevX = x;
      prevY = y;
      out[i] = y;
    }
  }
  // 4) 톤 성분 믹스 (crackle 미세 핑 등).
  if (spec.toneHz > 0 && spec.toneMix > 0) {
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final tone = math.sin(2 * math.pi * spec.toneHz * t);
      out[i] = out[i] * (1 - spec.toneMix) + tone * spec.toneMix;
    }
  }
  // 5) 엔벨로프 (어택 + 지수 감쇠) + 진폭 워블.
  final attackSamples = (n * spec.attack).clamp(1, n).toDouble();
  for (var i = 0; i < n; i++) {
    final frac = i / n;
    final atk = i < attackSamples ? i / attackSamples : 1.0;
    final env = atk * math.exp(-spec.decay * frac);
    var amp = env;
    if (spec.wobble > 0) {
      final w = 1 - spec.wobble * (0.5 + 0.5 * math.sin(
          2 * math.pi * spec.wobbleHz * (i / sampleRate)));
      amp *= w;
    }
    out[i] *= amp;
  }
  // 6) 피크 정규화 (클리핑 방지, 헤드룸 0.9).
  var peak = 0.0;
  for (final s in out) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak > 0) {
    final g = 0.9 / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= g;
    }
  }
  return out;
}

/// 샘플(-1~1) → 16-bit PCM mono WAV 바이트. soloud loadMem가 디코드한다.
Uint8List encodeWavMono16(List<double> samples, {int sampleRate = kSampleRate}) {
  final n = samples.length;
  final dataLen = n * 2;
  final bytes = Uint8List(44 + dataLen);
  final bd = ByteData.view(bytes.buffer);

  void writeStr(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  writeStr(0, 'RIFF');
  bd.setUint32(4, 36 + dataLen, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 1, Endian.little); // mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bd.setUint16(32, 2, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little); // bits per sample
  writeStr(36, 'data');
  bd.setUint32(40, dataLen, Endian.little);

  var off = 44;
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bd.setInt16(off, v, Endian.little);
    off += 2;
  }
  return bytes;
}

/// [spec] 그레인을 바로 WAV 바이트로.
Uint8List grainWav(GrainSpec spec, {int sampleRate = kSampleRate}) =>
    encodeWavMono16(synthGrain(spec, sampleRate: sampleRate),
        sampleRate: sampleRate);
