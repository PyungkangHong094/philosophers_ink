/// 노이즈 그레인 합성 단위 테스트 — WAV 헤더·길이·범위·결정성 (구조 검증).
///
/// 청감은 사람의 몫이지만, 버퍼가 유효한 PCM WAV이고 유한·범위 내·결정적인지는 검증한다.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/wav.dart';

String _fourcc(Uint8List b, int off) =>
    String.fromCharCodes(b.sublist(off, off + 4));

void main() {
  group('encodeWavMono16', () {
    test('유효한 RIFF/WAVE 헤더 + 올바른 길이', () {
      final wav = encodeWavMono16([0.0, 0.5, -0.5, 1.0], sampleRate: 44100);
      expect(_fourcc(wav, 0), 'RIFF');
      expect(_fourcc(wav, 8), 'WAVE');
      expect(_fourcc(wav, 12), 'fmt ');
      expect(_fourcc(wav, 36), 'data');
      final bd = ByteData.view(wav.buffer);
      expect(bd.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(bd.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(bd.getUint32(24, Endian.little), 44100, reason: 'sampleRate');
      expect(bd.getUint16(34, Endian.little), 16, reason: '16-bit');
      // 4 samples * 2 bytes = 8 data bytes + 44 header.
      expect(wav.length, 44 + 8);
      expect(bd.getUint32(40, Endian.little), 8, reason: 'data chunk size');
    });

    test('클리핑 방지 — |sample|>1도 안전 인코딩', () {
      final wav = encodeWavMono16([2.0, -2.0], sampleRate: 8000);
      final bd = ByteData.view(wav.buffer);
      expect(bd.getInt16(44, Endian.little), 32767);
      expect(bd.getInt16(46, Endian.little), -32767);
    });
  });

  group('synthGrain', () {
    test('예상 길이 + 유한 + 범위 내', () {
      final s = synthGrain(const GrainSpec(ms: 50), sampleRate: 44100);
      expect(s.length, (44100 * 50 / 1000).round());
      for (final v in s) {
        expect(v.isFinite, isTrue);
        expect(v.abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('결정적 — 같은 seed는 같은 출력', () {
      final a = synthGrain(const GrainSpec(ms: 30, seed: 42));
      final b = synthGrain(const GrainSpec(ms: 30, seed: 42));
      expect(a, b);
    });

    test('다른 seed는 다른 출력 (변주)', () {
      final a = synthGrain(const GrainSpec(ms: 30, seed: 1));
      final b = synthGrain(const GrainSpec(ms: 30, seed: 2));
      expect(a, isNot(equals(b)));
    });

    test('엔벨로프 — 끝부분이 앞부분보다 조용하다 (감쇠)', () {
      final s = synthGrain(const GrainSpec(ms: 100, seed: 7, decay: 8));
      double energy(int from, int to) {
        var e = 0.0;
        for (var i = from; i < to; i++) {
          e += s[i] * s[i];
        }
        return e / (to - from);
      }

      final head = energy(0, s.length ~/ 4);
      final tail = energy(s.length * 3 ~/ 4, s.length);
      expect(tail, lessThan(head), reason: '감쇠 엔벨로프');
    });
  });
}
