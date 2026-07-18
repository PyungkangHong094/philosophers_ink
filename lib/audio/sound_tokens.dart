/// 사운드 토큰 (GDD 9). 절차 합성 SFX의 주파수·볼륨·길이·믹스 계층 상수 단일 소스.
///
/// 오디오 에셋이 아직 없어 flutter_soloud 파형 오실레이터로 1차 SFX를 코드 생성한다.
/// 믹스 계층(GDD 9.2): 이벤트 SFX 0dB > 파티클 그레인 −6dB > BGM −9~−12dB.
/// 위젯/서비스 코드에 매직 수치 금지 — 전부 여기 참조.
library;

import 'dart:math' as math;

/// dB → 선형 게인 (0dB=1.0). 믹스 계층을 사람이 읽는 dB로 적고 여기서 변환.
double gainFromDb(double db) => math.pow(10, db / 20.0).toDouble();

/// 카테고리 믹스 게인 (GDD 9.2 믹스 계층).
abstract final class SfxMix {
  static const double eventDb = 0.0; // 이벤트 SFX 기준
  static const double grainDb = -6.0; // 파티클 그레인
  static const double bgmDb = -10.0; // BGM (−9~−12 중앙)

  static final double event = gainFromDb(eventDb);
  static final double grain = gainFromDb(grainDb);
  static final double bgm = gainFromDb(bgmDb);
}

/// 이벤트별 절차 합성 스펙 (기본 주파수 Hz, 볼륨 0~1, 릴리스).
abstract final class SfxSpec {
  // UI 탭 — 짧고 밝은 사각파 클릭.
  static const double uiTapFreq = 880.0; // A5
  static const double uiTapVol = 0.28;
  static const int uiTapMs = 45;

  // 드로잉 획 — 낮고 부드러운 삼각파 틱 (드래그 중 스로틀).
  static const double strokeFreq = 196.0; // G3
  static const double strokeVol = 0.16;
  static const int strokeMs = 32;
  static const int strokeThrottleMs = 45; // 최소 재생 간격

  // 플라스크 착수 틱 — 상(phase)별 피치. 카운트업 동기(GDD 9.2 최우선 폴리시).
  static const double flaskBaseFreq = 660.0;
  static const double flaskSolidFreq = 784.0; // G5 — 딱딱한 고음
  static const double flaskLiquidFreq = 587.0; // D5 — 중간
  static const double flaskGasFreq = 494.0; // B4 — 낮고 공기감
  static const double flaskVol = 0.22;
  static const int flaskMs = 55;

  // 클리어 스팅어 — 상승 3음 아르페지오 (C5·E5·G5).
  static const List<double> clearArp = [523.25, 659.25, 783.99];
  static const double clearVol = 0.34;
  static const int clearNoteMs = 180;
  static const int clearStaggerMs = 90;

  // 작업(OPERATIO) 전용 스팅어 — 낮고 풍성한 4음 (G4·C5·E5·G5), 사각파.
  static const List<double> operatioArp = [392.0, 523.25, 659.25, 783.99];
  static const double operatioVol = 0.36;
  static const int operatioNoteMs = 220;
  static const int operatioStaggerMs = 110;

  // 실패(오염) — 하강 2음 (E4·C4), 톱니파.
  static const List<double> failArp = [329.63, 261.63];
  static const double failVol = 0.30;
  static const int failNoteMs = 200;
  static const int failStaggerMs = 120;

  // 물질 앰비언트 그레인 — 활성 셀 밀도로 볼륨 변조하는 저역 루프.
  static const double grainFreq = 110.0; // A2
  static const double grainMaxVol = 0.5; // 밀도 1.0일 때 목표(그레인 믹스 전)
  static const int grainSampleEveryFrames = 12; // ~5Hz 갱신
  static const int grainRampMs = 160;

  /// 밀도 정규화 기준 셀 수 — 이만큼 활성이면 그레인 최대(≈51k 셀 중 "붐비는" 장면).
  static const int grainRefCells = 6000;

  /// 변주 디튠 최대치(센트). 각 재생마다 ±범위 랜덤으로 반복감 제거(GDD 9.2).
  static const double detuneCents = 14.0;
}
