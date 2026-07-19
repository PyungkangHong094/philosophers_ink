/// 오디오 서비스 단위 테스트 — 무음 폴백 + SoLoud 미초기화 시 안전 무음(무예외) +
/// 드론 방지 구조 가드(연속 루프는 BGM뿐, 그레인은 전부 짧은 원샷).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/audio/soloud_audio_service.dart';
import 'package:philosophers_ink/audio/sound_tokens.dart';
import 'package:philosophers_ink/level/level_model.dart' show FlaskState;

void main() {
  test('SilentAudioService는 모든 이벤트가 no-op (무예외)', () {
    const a = SilentAudioService();
    expect(() {
      a.configure(enabled: true, volume: 0.5, bgmEnabled: true);
      a.uiTap();
      a.stroke();
      a.flaskFill(FlaskState.solid, progress: 0.5);
      a.flaskFill(null);
      a.clearStinger();
      a.operatioStinger();
      a.fail();
      a.phaseTransition(PhaseSfx.crackle);
      a.phaseTransition(PhaseSfx.puff);
      a.phaseTransition(PhaseSfx.sizzle);
      a.setAmbience(particle: 0.7, water: 0.3, steam: 0.1);
      a.setBgmChapter(2);
      a.stopAmbient();
      a.stopAll();
    }, returnsNormally);
  });

  test('SoLoudAudioService는 init 없이도 안전하게 무음 (FFI 미접근)', () {
    final a = SoLoudAudioService();
    expect(() {
      a.configure(enabled: true, volume: 1.0, bgmEnabled: true);
      a.uiTap();
      a.stroke();
      a.flaskFill(FlaskState.liquid, progress: 0.9);
      a.clearStinger();
      a.operatioStinger();
      a.fail();
      a.phaseTransition(PhaseSfx.sizzle);
      a.setAmbience(particle: 1.0, water: 1.0, steam: 1.0);
      a.setBgmChapter(1);
      a.stopAmbient();
      a.stopAll();
    }, returnsNormally);
  });

  test('음소거(enabled=false) 설정 시에도 무예외', () {
    final a = SoLoudAudioService();
    a.configure(enabled: false, volume: 0.0, bgmEnabled: false);
    expect(() {
      a.uiTap();
      a.setAmbience(particle: 0.5, water: 0, steam: 0);
      a.setBgmChapter(3);
    }, returnsNormally);
  });

  group('드론 방지 구조 가드 (P1 "지잉" 회귀 방지)', () {
    test('BGM은 기본 OFF (유일한 연속 루프)', () {
      expect(BgmSpec.defaultEnabled, isFalse);
    });

    test('모든 그레인은 짧은 원샷(≤300ms) — 지속 톤 불가', () {
      final all = [
        ...GrainKit.crackle,
        ...GrainKit.puff,
        ...GrainKit.sizzle,
        ...GrainKit.particle,
        ...GrainKit.water,
        ...GrainKit.steam,
      ];
      for (final g in all) {
        expect(g.ms, lessThanOrEqualTo(300),
            reason: '그레인 길이 ${g.ms}ms — 짧아야 드론이 안 된다');
        expect(g.ms, greaterThan(0));
      }
    });

    test('이벤트/그레인 변주 3~5개', () {
      expect(GrainKit.crackle.length, inInclusiveRange(3, 5));
      expect(GrainKit.puff.length, inInclusiveRange(3, 5));
      expect(GrainKit.sizzle.length, inInclusiveRange(3, 5));
      expect(GrainKit.particle.length, inInclusiveRange(3, 5));
      expect(GrainKit.water.length, inInclusiveRange(3, 5));
      expect(GrainKit.steam.length, inInclusiveRange(3, 5));
    });

    test('믹스 계층: 이벤트 > 그레인 ≥ BGM (GDD 9.2)', () {
      expect(SfxMix.event, greaterThan(SfxMix.grain));
      expect(SfxMix.grain, greaterThanOrEqualTo(SfxMix.bgm));
    });

    test('착수 틱 스로틀 존재 (빠른 착수 버즈 방지)', () {
      expect(SfxSpec.flaskThrottleMs, greaterThanOrEqualTo(50));
    });
  });
}
