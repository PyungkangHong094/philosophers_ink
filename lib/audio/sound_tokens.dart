/// 사운드 토큰 (GDD 9) — 절차 합성 SFX/그레인/BGM의 모든 파라미터 단일 소스.
///
/// 매직 넘버 금지: 위젯·서비스는 전부 여기 참조. 믹스 계층(GDD 9.2): 이벤트 0dB >
/// 그레인 −6dB > BGM −9~−12dB. 노이즈 그레인 스펙은 [GrainSpec](wav.dart)로 정의한다.
library;

import 'dart:math' as math;

import 'wav.dart';

/// dB → 선형 게인 (0dB=1.0).
double gainFromDb(double db) => math.pow(10, db / 20.0).toDouble();

/// 카테고리 믹스 게인 (GDD 9.2 믹스 계층).
abstract final class SfxMix {
  static const double eventDb = 0.0; // 이벤트 SFX 기준
  static const double phaseDb = -3.0; // 상전이 SFX (이벤트 계열, 약간 아래)
  static const double grainDb = -9.0; // 파티클 그레인 (보수적 — 드론 실패 재발 방지)
  static const double ambientDb = -9.0; // 물질 앰비언트
  static const double bgmDb = -12.0; // BGM (−9~−12 중 최하)

  static final double event = gainFromDb(eventDb);
  static final double phase = gainFromDb(phaseDb);
  static final double grain = gainFromDb(grainDb);
  static final double ambient = gainFromDb(ambientDb);
  static final double bgm = gainFromDb(bgmDb);
}

/// 재생 시 무작위 변주 (반복감 제거, GDD 9.2 "변주 3~5개").
abstract final class SfxVary {
  /// 톤 SFX 주파수 지터(±센트).
  static const double freqCents = 22.0;
  /// 볼륨 지터(±비율).
  static const double vol = 0.12;
  /// 길이 지터(±비율).
  static const double len = 0.12;
}

/// 톤 이벤트 SFX 기본 파라미터. 변주는 [SfxVary]로 재생 시 지터한다.
abstract final class SfxSpec {
  // UI 탭.
  static const double uiTapFreq = 880.0;
  static const double uiTapVol = 0.26;
  static const int uiTapMs = 45;
  /// 배음 층(어택 반짝) — 기본 주파수의 배수 + 믹스.
  static const double uiTapHarmonic = 2.0;
  static const double uiTapHarmonicMix = 0.25;

  // 드로잉 획.
  static const double strokeFreq = 196.0;
  static const double strokeVol = 0.15;
  static const int strokeMs = 30;
  static const int strokeThrottleMs = 45;

  // 플라스크 착수 틱 — 상별 기본 피치 + 카운트업 램프.
  static const double flaskSolidFreq = 784.0; // G5
  static const double flaskLiquidFreq = 587.0; // D5
  static const double flaskGasFreq = 494.0; // B4
  static const double flaskBaseFreq = 660.0;
  static const double flaskVol = 0.22;
  static const int flaskMs = 55;
  static const int flaskThrottleMs = 70;
  /// 카운트업 동기 — 채움 진행도 0~1에 따라 피치를 최대 이만큼 반음 올린다(만족 커브).
  static const double flaskRampSemitones = 12.0;

  // 클리어 스팅어 (상승 아르페지오).
  static const List<double> clearArp = [523.25, 659.25, 783.99];
  static const double clearVol = 0.32;
  static const int clearNoteMs = 180;
  static const int clearStaggerMs = 90;

  // 작업(OPERATIO) 스팅어 (낮고 풍성).
  static const List<double> operatioArp = [392.0, 523.25, 659.25, 783.99];
  static const double operatioVol = 0.34;
  static const int operatioNoteMs = 220;
  static const int operatioStaggerMs = 110;

  // 실패(오염) — 하강.
  static const List<double> failArp = [329.63, 261.63];
  static const double failVol = 0.30;
  static const int failNoteMs = 200;
  static const int failStaggerMs = 120;
}

/// 노이즈 그레인 키트 (GDD 9.2 이벤트 SFX 결빙/증발/반응 + 파티클 그레인 + 물질 앰비언트).
///
/// 전부 짧은 원샷 그레인이다(연속 루프 없음) — "지잉" 드론이 구조적으로 불가능.
abstract final class GrainKit {
  // 결빙 crackle (ICE 생성) — 밝고 바삭. 변주 3.
  static const List<GrainSpec> crackle = [
    GrainSpec(ms: 70, seed: 11, lowpass: 0.6, highpass: 0.3, decay: 9, toneHz: 2100, toneMix: 0.15),
    GrainSpec(ms: 64, seed: 23, lowpass: 0.55, highpass: 0.35, decay: 10, toneHz: 2600, toneMix: 0.12),
    GrainSpec(ms: 78, seed: 37, lowpass: 0.65, highpass: 0.28, decay: 8, toneHz: 1800, toneMix: 0.18),
  ];

  // 증발 puff (STEAM 생성) — 부드럽고 공기감. 변주 3.
  static const List<GrainSpec> puff = [
    GrainSpec(ms: 130, seed: 41, lowpass: 0.25, highpass: 0.05, attack: 0.15, decay: 3),
    GrainSpec(ms: 120, seed: 53, lowpass: 0.22, highpass: 0.06, attack: 0.18, decay: 3.4),
    GrainSpec(ms: 145, seed: 67, lowpass: 0.28, highpass: 0.04, attack: 0.12, decay: 2.6),
  ];

  // 반응 시즐 (LAVA+WATER) — 길고 지글. 변주 3.
  static const List<GrainSpec> sizzle = [
    GrainSpec(ms: 180, seed: 71, lowpass: 0.4, decay: 2.5, wobble: 0.4, wobbleHz: 22),
    GrainSpec(ms: 165, seed: 83, lowpass: 0.45, decay: 2.8, wobble: 0.45, wobbleHz: 26),
    GrainSpec(ms: 195, seed: 97, lowpass: 0.38, decay: 2.2, wobble: 0.35, wobbleHz: 18),
  ];

  // 파티클 그레인 (입자 낙하·퇴적) — 아주 짧은 클릭. 변주 5.
  static const List<GrainSpec> particle = [
    GrainSpec(ms: 26, seed: 101, lowpass: 0.5, decay: 10, attack: 0.05),
    GrainSpec(ms: 30, seed: 113, lowpass: 0.45, decay: 9, attack: 0.05),
    GrainSpec(ms: 22, seed: 127, lowpass: 0.55, decay: 12, attack: 0.04),
    GrainSpec(ms: 28, seed: 139, lowpass: 0.48, decay: 10, attack: 0.06),
    GrainSpec(ms: 24, seed: 151, lowpass: 0.52, decay: 11, attack: 0.05),
  ];

  // 물 흐름 앰비언트 — 로우 노이즈 워블. 변주 4.
  static const List<GrainSpec> water = [
    GrainSpec(ms: 95, seed: 201, lowpass: 0.35, decay: 3, wobble: 0.5, wobbleHz: 6),
    GrainSpec(ms: 110, seed: 211, lowpass: 0.32, decay: 2.8, wobble: 0.55, wobbleHz: 5),
    GrainSpec(ms: 88, seed: 223, lowpass: 0.38, decay: 3.2, wobble: 0.45, wobbleHz: 7),
    GrainSpec(ms: 102, seed: 233, lowpass: 0.34, decay: 3, wobble: 0.5, wobbleHz: 6.5),
  ];

  // 증기 히스 앰비언트 — 하이패스 노이즈. 변주 4.
  static const List<GrainSpec> steam = [
    GrainSpec(ms: 110, seed: 301, highpass: 0.5, decay: 2.5, attack: 0.1),
    GrainSpec(ms: 120, seed: 311, highpass: 0.55, decay: 2.3, attack: 0.12),
    GrainSpec(ms: 100, seed: 323, highpass: 0.48, decay: 2.7, attack: 0.09),
    GrainSpec(ms: 115, seed: 331, highpass: 0.52, decay: 2.4, attack: 0.11),
  ];
}

/// 상전이·그레인·앰비언트 재생 파라미터.
abstract final class GrainPlay {
  /// 지속 앰비언트 층(파티클 그레인·물/증기 워블) 마스터 스위치.
  /// **기본 OFF** — 저역 웅웅거림("우웅")이 거슬린다는 실플레이 피드백(2026-07-19).
  /// 이벤트 SFX(획·착수·상전이·스팅어)와는 무관하며, 설정 토글로만 켠다.
  static const bool ambientLayersDefaultEnabled = false;

  // 상전이 SFX 볼륨 + 위치·밀도 스로틀.
  static const double crackleVol = 0.5;
  static const double puffVol = 0.45;
  static const double sizzleVol = 0.5;
  /// 스로틀 윈도(ms)와 윈도당 최대 재생 수. 초과분은 볼륨만 가산(밀도 감).
  static const int phaseWindowMs = 100;
  static const int phaseMaxPerWindow = 2;

  // 파티클 그레인 — 밀도 샘플 주기(프레임)와 그레인 발사.
  static const int sampleEveryFrames = 12; // ≈5Hz
  static const double grainVol = 0.6; // 그레인 믹스 전 기본
  /// 밀도(0~1) → 이번 샘플에 발사할 그레인 수(반올림, 최대).
  static const double grainDensityToCount = 2.2;
  static const int grainMaxPerSample = 2;
  /// 밀도 → 재생 속도(피치). 낮은 밀도=낮은 피치. 0.8~1.3.
  static const double grainSpeedMin = 0.8;
  static const double grainSpeedMax = 1.3;
  /// 밀도 정규화 기준 셀 수(≈51k 중 "붐비는" 장면).
  static const int densityRefCells = 6000;

  // 물질 앰비언트 — 물/증기 밀도 → 그레인 발사(파티클과 유사, 더 성김).
  static const double ambientDensityToCount = 1.4;
  static const int ambientMaxPerSample = 1;
  static const double waterVol = 0.55;
  static const double steamVol = 0.5;
  /// 물/증기 밀도 정규화 기준 셀 수(입자보다 적어도 들리게 낮춤).
  static const int ambientRefCells = 2500;
}

/// 절차 BGM (챕터별 미니멀 앰비언트 패드). 에셋 없이 절차 드론이라 품질 한계 →
/// **기본 OFF**, 설정 별도 토글. 클리어 시 덕킹(GDD 9.2).
abstract final class BgmSpec {
  static const bool defaultEnabled = false;

  /// 챕터별 패드 근음(Hz). 니그레도 저음 → 루베도 약간 높게(팔레트 톤 변화 근사).
  static const List<double> chapterRoot = [
    98.0, // 1 니그레도 G2
    110.0, // 2 알베도 A2
    123.47, // 3 키트리니타스 B2
    130.81, // 4 루베도 C3
  ];
  /// 패드 화음 간격(반음) — 근음 + 5도 + 옥타브(개방적).
  static const List<double> chordSemitones = [0, 7, 12];
  static const double padVol = 0.5; // bgm 믹스 전 기본(낮음)
  /// 덕킹: 클리어 스팅어 동안 이 배수로 감쇠.
  static const double duckFactor = 0.35;
  static const int duckMs = 900;
}
