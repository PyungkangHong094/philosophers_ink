/// 오디오 서비스 계약 (GDD 9). 셸·인게임이 의미 이벤트만 호출하고, 합성/믹스는 구현이 맡는다.
///
/// 실제 구현은 [SoLoudAudioService](flutter_soloud 절차 합성). 테스트·미지원 플랫폼·초기화
/// 실패 시 [SilentAudioService]로 폴백한다 — 호출부는 서비스 종류를 몰라도 된다.
library;

import '../level/level_model.dart' show FlaskState;

/// 상전이 SFX 종류. sim은 (materialFrom, materialTo) 쌍으로 전이를 보고하고, PlayScreen이
/// materialTo → 이 enum으로 매핑한다(오디오가 sim 물질 ID에 직접 결합되지 않게).
enum PhaseSfx {
  crackle, // 결빙 (ICE 생성)
  puff, // 증발 (STEAM 생성)
  sizzle, // 반응 (LAVA+WATER)
}

/// 셸/인게임이 부르는 의미 이벤트 집합.
abstract class AudioService {
  /// 엔진 초기화 + SFX/그레인 소스 프리로드. 실패해도 예외를 던지지 않고 무음화한다.
  Future<void> init();

  Future<void> dispose();

  /// 설정 반영 — 음소거(enabled=false)·마스터 볼륨(0~1)·BGM 토글. 설정 변경마다 호출.
  void configure({
    required bool enabled,
    required double volume,
    required bool bgmEnabled,
  });

  // ---- 이벤트 SFX ----
  void uiTap();
  void stroke();

  /// 플라스크 착수 틱 — 상(phase)별 피치 + [progress](채움 0~1)로 카운트업 피치 램프(GDD 9.2).
  void flaskFill(FlaskState? phase, {double progress});

  void clearStinger();
  void operatioStinger();
  void fail();

  /// 상전이 SFX (결빙 crackle·증발 puff·반응 sizzle). 틱당 다수 발생 — 구현이 스로틀한다.
  void phaseTransition(PhaseSfx kind);

  // ---- 지속 레이어 (그레인·앰비언트) ----
  /// 활성 밀도(0~1)로 파티클 그레인·물/증기 앰비언트를 확률적으로 발사(수직 적응형, GDD 9.2).
  /// 연속 루프가 아니라 짧은 그레인이라 드론이 되지 않는다.
  void setAmbience({
    required double particle,
    required double water,
    required double steam,
  });

  /// 인게임 진입 시 BGM 챕터 설정(팔레트별 근음). 0이면 정지.
  void setBgmChapter(int chapter);

  /// 인게임 이탈 시 앰비언트·그레인 정지(원샷 SFX는 자연 종료).
  void stopAmbient();

  /// 모든 루프성/지속 재생(앰비언트·BGM)을 즉시 정지. 화면 dispose·앱 백그라운드 시 호출.
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
  void configure({
    required bool enabled,
    required double volume,
    required bool bgmEnabled,
  }) {}
  @override
  void uiTap() {}
  @override
  void stroke() {}
  @override
  void flaskFill(FlaskState? phase, {double progress = 0}) {}
  @override
  void clearStinger() {}
  @override
  void operatioStinger() {}
  @override
  void fail() {}
  @override
  void phaseTransition(PhaseSfx kind) {}
  @override
  void setAmbience({
    required double particle,
    required double water,
    required double steam,
  }) {}
  @override
  void setBgmChapter(int chapter) {}
  @override
  void stopAmbient() {}
  @override
  void stopAll() {}
}
