/// 셸(아웃게임) 디자인 토큰 — GDD 8.4 + ink-shell-design 스킬의 SSOT를 Flutter 상수로.
///
/// 원칙: 위젯 코드에 hex·매직 수치 직접 기입 금지. 색·간격·타이포·모션은 전부 여기서 참조.
/// 트루 블랙(그을린 웜 블랙) + 골드 1계열, 유채색은 챕터 스와치 4색만 셸에 허용.
library;

import 'package:flutter/widgets.dart';

/// 표면·골드·텍스트·챕터 스와치 색 토큰 (GDD 8.4.2).
abstract final class InkColor {
  // 표면 — 그을린 웜 블랙 (순수 무채 금지).
  static const Color black0 = Color(0xFF050505); // 최심부 (타이틀·결과 배경)
  static const Color black1 = Color(0xFF0A0A09); // 기본 캔버스
  static const Color black2 = Color(0xFF131311); // 카드·패널
  static const Color black3 = Color(0xFF1D1C19); // 엘리베이티드·프레스
  static const Color hairline = Color(0xFF29271F); // 보더 (골드 기운 도는 헤어라인)

  // 골드 — 악센트 1계열. 화면당 1~2개만.
  static const Color gold = Color(0xFFC9A227); // 기본 — CTA·선택·별
  static const Color goldHi = Color(0xFFE8C95A); // 글로우 코어·프레스 하이라이트
  static const Color goldDeep = Color(0xFF8F7118); // 섀도·비활성 골드

  // 텍스트 — 순백 금지, 양피지 뉘앙스.
  static const Color parchment = Color(0xFFF2EDDF); // 주 텍스트
  static const Color text2 = Color(0xFF9C968A); // 보조
  static const Color text3 = Color(0xFF5E5A50); // 비활성·힌트

  /// 경고 — 카운트다운 임박(≤10초) 강조 (GDD 2장). 골드 아님(골드 희소성 보존).
  static const Color warn = Color(0xFFD9542B); // 주홍 경고

  // 챕터 스와치 (셸에 허용되는 유일한 유채색, GDD 7.1).
  static const Color nigredo = Color(0xFF1D1418);
  static const Color albedo = Color(0xFFE9E5DB);
  static const Color citrinitas = Color(0xFFD9A62E);
  static const Color rubedo = Color(0xFF8E1F2F);

  /// 오버레이 — 일시정지/결과의 챕터색 차단막 (블러 금지, 명도로만).
  static const Color scrim90 = Color(0xE6050505); // black0 90%
}

/// 인게임 월드 오버레이 마커 색 (GDD 6·8.1). **셸 무채 규칙의 예외** — 인게임은 화려하게.
/// 기믹·방출구 정적 표식 전용이며 셸 화면에는 등장하지 않는다. 각 색은 챕터 4색 배경 모두에서
/// 식별되도록 페인터가 배경 명도에 맞춘 적응형 헤일로(어두운 배경엔 밝은, 밝은 배경엔 어두운
/// 외곽선)와 함께 그린다 — 볼드한 단색 실루엣 + 명도 대비 20%+ (GDD 8.1).
abstract final class InkGimmick {
  /// 온도 존 — 열(화로): 주홍. 물질 테이블 LAVA/HEAT 색과 동계열.
  static const Color heatZone = Color(0xFFE0602A);

  /// 온도 존 — 냉(빙결): 청백. ICE/FROST 색과 동계열.
  static const Color coolZone = Color(0xFF6BC4E8);

  /// 포탈 페어 색 — **같은 색 = 연결된 입·출구 페어**. 페어 인덱스로 순환한다.
  /// (셸 스와치와 겹치지 않는 인게임 전용 채도.)
  static const List<Color> portalPairs = [
    Color(0xFF32C8D8), // 0 시안
    Color(0xFFD85AC0), // 1 마젠타
    Color(0xFF8FD048), // 2 라임
    Color(0xFFE0A93A), // 3 앰버
  ];
}

/// 모션 duration 토큰 (GDD 8.4.5). 셸 전환은 "의식"처럼 무게감 있게.
abstract final class InkMotion {
  static const Duration fast = Duration(milliseconds: 120); // 프레스 피드백
  static const Duration base = Duration(milliseconds: 240); // 화면 페이드
  static const Duration ritual = Duration(milliseconds: 650); // 플러드·별 스탬프
  static const Duration starStagger = Duration(milliseconds: 250); // 별 스탬프 간격

  /// 잉크 플러드 곡선.
  static const Curve flood = Curves.easeInOutQuart;

  /// 별 스탬프 오버슛.
  static const Curve stamp = Curves.easeOutBack;
}

/// 간격 스케일 (8pt 그리드). 매직 넘버 방지.
abstract final class InkSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
  static const double xxl = 64;

  /// 샤프 모서리 (람보르기니 각) — 카드·버튼 공통 radius.
  static const double radius = 2;

  /// 레벨 셀 최소 변 (터치 타겟 56px, GDD 8.4.7).
  static const double levelCell = 56;

  /// 일반 터치 타겟 최소.
  static const double touchTarget = 44;
}

/// 타이포 토큰 (GDD 8.4.3). 한/영 이중 전략.
///
/// 폰트 에셋(Anton 계열/Pretendard)이 아직 assets/fonts/에 없어 시스템 폴백으로
/// 진행한다 (TODO: M5 폴리시에서 에셋 번들 + family 지정). Display 역할은 시스템
/// 폰트에 w900 + 대문자 + 자간으로 근사한다.
abstract final class InkText {
  /// Display(라틴) 패밀리 — 미탑재. null이면 시스템 폴백.
  static const String? displayFamily = null; // TODO(M5): 'Anton'
  /// 한글·본문 패밀리 — 미탑재. null이면 시스템 폴백.
  static const String? textFamily = null; // TODO(M5): 'Pretendard'

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Display XL — 레벨 번호 등 초대형 라틴 (대문자 전용).
  static const TextStyle displayXL = TextStyle(
    fontFamily: displayFamily,
    fontSize: 92,
    fontWeight: FontWeight.w900,
    letterSpacing: 2.5,
    height: 0.95,
    color: InkColor.parchment,
    fontFeatures: tabular,
  );

  /// Display L — 챕터명 라틴 대문자.
  static const TextStyle displayL = TextStyle(
    fontFamily: displayFamily,
    fontSize: 46,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.8,
    color: InkColor.parchment,
  );

  /// Display M — 로고 행/중형 라틴.
  static const TextStyle displayM = TextStyle(
    fontFamily: displayFamily,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: InkColor.parchment,
  );

  /// 한글 대형 헤딩 (900, 음수 자간).
  static const TextStyle headingKo = TextStyle(
    fontFamily: textFamily,
    fontSize: 44,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.9,
    color: InkColor.parchment,
  );

  /// 한글 중형 헤딩.
  static const TextStyle titleKo = TextStyle(
    fontFamily: textFamily,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: InkColor.parchment,
  );

  /// 본문 15px.
  static const TextStyle body = TextStyle(
    fontFamily: textFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: InkColor.text2,
    height: 1.4,
  );

  /// 캡션 12px.
  static const TextStyle caption = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: InkColor.text2,
    fontFeatures: tabular,
  );

  /// 아이브로우 — 11px 대문자 넓은 자간 (MAGNUM OPUS 등).
  static const TextStyle eyebrow = TextStyle(
    fontFamily: textFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 3.0,
    color: InkColor.text2,
  );

  /// CTA 라벨 (골드 필 위 black0, 800).
  static const TextStyle cta = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    color: InkColor.black0,
  );
}
