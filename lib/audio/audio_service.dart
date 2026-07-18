/// 오디오 서비스 계약 (GDD 9). 셸·인게임이 의미 이벤트만 호출하고, 합성/믹스는 구현이 맡는다.
///
/// 실제 구현은 [SoLoudAudioService](flutter_soloud 절차 합성). 테스트·미지원 플랫폼·초기화
/// 실패 시 [SilentAudioService]로 폴백한다 — 호출부는 서비스 종류를 몰라도 된다.
library;

import '../level/level_model.dart' show FlaskState;

/// 셸/인게임이 부르는 의미 이벤트 집합.
abstract class AudioService {
  /// 엔진 초기화 + SFX 소스 프리로드. 실패해도 예외를 던지지 않고 무음화한다.
  Future<void> init();

  Future<void> dispose();

  /// 설정 반영 — 음소거(enabled=false)·마스터 볼륨(0~1). 설정 변경마다 호출.
  void configure({required bool enabled, required double volume});

  // ---- 이벤트 SFX ----
  void uiTap();
  void stroke();

  /// 플라스크 착수 틱 — 상(phase)별 피치. 카운트업과 동기(GDD 9.2).
  void flaskFill(FlaskState? phase);

  void clearStinger();
  void operatioStinger();
  void fail();

  /// 물질 앰비언트 그레인 볼륨 변조 — 활성 셀 밀도 0~1 (GDD 9.2 수직 적응형).
  void setAmbientDensity(double normalized);

  /// 인게임 이탈 시 앰비언트 정지.
  void stopAmbient();

  /// 모든 루프성/지속 재생(앰비언트·향후 BGM)을 즉시 정지한다. 원샷 SFX는 자연 종료라 무관.
  /// 화면 dispose·앱 백그라운드 전환 시 호출해 전역 루프 핸들 잔존을 막는다.
  void stopAll();
}

/// 무음 폴백 — 전 메서드 no-op. 테스트 기본값.
class SilentAudioService implements AudioService {
  const SilentAudioService();

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
  @override
  void configure({required bool enabled, required double volume}) {}
  @override
  void uiTap() {}
  @override
  void stroke() {}
  @override
  void flaskFill(FlaskState? phase) {}
  @override
  void clearStinger() {}
  @override
  void operatioStinger() {}
  @override
  void fail() {}
  @override
  void setAmbientDensity(double normalized) {}
  @override
  void stopAmbient() {}
  @override
  void stopAll() {}
}
