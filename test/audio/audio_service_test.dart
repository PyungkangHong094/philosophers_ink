/// 오디오 서비스 단위 테스트 — 무음 폴백 + SoLoud 미초기화 시 안전 무음(무예외).
///
/// 헤드리스 테스트에서 SoLoud FFI를 초기화하지 않는다. 목표는 "오디오가 게임을 죽이지
/// 않는다" — init을 부르지 않은 SoLoudAudioService의 모든 이벤트가 no-op이어야 한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/audio/soloud_audio_service.dart';
import 'package:philosophers_ink/audio/sound_tokens.dart';
import 'package:philosophers_ink/level/level_model.dart' show FlaskState;

void main() {
  // P1 회귀 가드: 밀도 기반 앰비언트 그레인은 연속 "지잉" 드론이 되므로 기본 OFF다.
  // sim 이동 이벤트 훅으로 이벤트 기반 재설계 전까지 이 값을 true로 바꾸지 말 것.
  test('앰비언트 그레인은 기본 OFF (P1 지잉 소음 회귀 가드)', () {
    expect(SfxSpec.ambientGrainEnabled, isFalse);
  });

  test('착수 틱 스로틀 간격이 설정돼 있다 (빠른 착수 버즈 방지)', () {
    expect(SfxSpec.flaskThrottleMs, greaterThanOrEqualTo(50));
  });

  test('SilentAudioService는 모든 이벤트가 no-op (무예외)', () {
    const a = SilentAudioService();
    expect(() {
      a.configure(enabled: true, volume: 0.5);
      a.uiTap();
      a.stroke();
      a.flaskFill(FlaskState.solid);
      a.flaskFill(null);
      a.clearStinger();
      a.operatioStinger();
      a.fail();
      a.setAmbientDensity(0.7);
      a.stopAmbient();
    }, returnsNormally);
  });

  test('SoLoudAudioService는 init 없이도 안전하게 무음 (FFI 미접근)', () {
    final a = SoLoudAudioService();
    // init을 부르지 않았으므로 _ready=false → 전 이벤트가 엔진을 건드리지 않고 반환.
    expect(() {
      a.configure(enabled: true, volume: 1.0);
      a.uiTap();
      a.stroke();
      a.flaskFill(FlaskState.liquid);
      a.clearStinger();
      a.operatioStinger();
      a.fail();
      a.setAmbientDensity(1.0);
      a.stopAmbient();
    }, returnsNormally);
  });

  test('음소거(enabled=false) 설정 시에도 무예외', () {
    final a = SoLoudAudioService();
    a.configure(enabled: false, volume: 0.0);
    expect(() {
      a.uiTap();
      a.setAmbientDensity(0.5);
    }, returnsNormally);
  });
}
