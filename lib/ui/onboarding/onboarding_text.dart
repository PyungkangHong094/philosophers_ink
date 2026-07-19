/// 온보딩 문구 생성 (GDD 7.2 튜토리얼 원칙 — 텍스트 최소화, 1줄). 순수 로직.
///
/// 플라스크 조건(개수/물질/상태/순수)에서 목표 1줄을 자동 생성하고, 별점 임계 문구를 만든다.
/// 하드코딩 색·위젯 없음 — 위젯 계층이 이 문자열을 토큰 스타일로 그린다.
///
/// **어미 톤 3분할 규칙 (UI 문구 감사 확정 — 이후 문구 추가 시 준수):**
///  - 기능 문구(목표·조작 안내, 버튼) = **명사형 -기** (예: "플라스크 3개 채우기", "선을 그어 길 만들기").
///  - 시스템 알림(설정 스낵바·실패 안내 등) = **-어요/-했어요체** (예: "안내를 초기화했어요").
///  - 장식 타이틀(클리어·실패 제목)만 담백한 서술체 유지 (예: "정제 완료").
///  "-어라" 해라체 명령형은 전면 폐기. 셀 수 있는 대상(플라스크 개수)엔 "만큼"이 아니라 "개".
library;

import '../../gameplay/star_rating.dart';
import '../../level/level_model.dart';

/// 물질 한글 표시명 (셸 로컬라이즈 — sim은 영문 name만 보유).
String materialDisplayKo(Material m) => switch (m) {
      Material.prima => '프리마',
      Material.water => '물',
      Material.ice => '얼음',
      Material.steam => '증기',
      Material.ash => '재',
      Material.lava => '용암',
      Material.stone => '돌',
      Material.wall => '벽',
      Material.heatLine => '화염선',
      Material.coldLine => '서리선',
      Material.empty => '',
    };

/// 상태 한글 표시명.
String flaskStateKo(FlaskState s) => switch (s) {
      FlaskState.solid => '고체',
      FlaskState.liquid => '액체',
      FlaskState.gas => '기체',
    };

/// 목적격 조사 부착 (을/를) — 한글 받침 유무로 판정. 비한글은 '을' 폴백.
String withEul(String word) {
  if (word.isEmpty) return word;
  final c = word.codeUnitAt(word.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '$word을';
  final hasBatchim = (c - 0xAC00) % 28 != 0;
  return '$word${hasBatchim ? '을' : '를'}';
}

/// 레벨 목표 1줄 (명사형 -기, 감사 확정). 플라스크 조건에서 파생.
/// 다중 플라스크는 요약 1줄로. 셀 수 있는 대상(플라스크)엔 "개".
String goalLine(Level level) => goalLineForFlasks(level.flasks);

String goalLineForFlasks(List<FlaskSpec> flasks) {
  if (flasks.isEmpty) return '플라스크 채우기';
  if (flasks.length != 1) {
    return '플라스크 ${flasks.length}개를 조건대로 채우기';
  }
  final f = flasks.single;
  final String core;
  if (f.state != null) {
    // 조사(을/를) 보완 + 명사형.
    final matPart =
        f.material != null ? '${withEul(materialDisplayKo(f.material!))} ' : '';
    core = '$matPart${flaskStateKo(f.state!)}로 ${f.goal}만큼 담기';
  } else if (f.material != null) {
    // 순수(재 없이)면 "플라스크에" 없이 간결하게 (감사안).
    core = f.pure
        ? '${materialDisplayKo(f.material!)} ${f.goal}만큼 담기'
        : '${withEul(materialDisplayKo(f.material!))} 플라스크에 ${f.goal}만큼 담기';
  } else {
    core = '플라스크 ${f.goal}개 채우기';
  }
  // 순수(❗) — 재 혼입 금지.
  return f.pure ? '재 없이 $core' : core;
}

/// 별점 임계 결과 (미검증 레벨이면 null 임계).
StarResult levelStarInfo(Level level) => computeStars(
      cleared: true,
      inkUsed: 0,
      optimalTotal: level.meta.optimalTotal,
      explicit: level.starThresholds,
    );

/// 일시정지·안내용 임계 1줄 ("★★ ≤ 42 · ★★★ ≤ 30"). 미검증이면 null.
String? starThresholdLine(Level level) {
  final r = levelStarInfo(level);
  final three = r.threeStarThreshold;
  final two = r.twoStarThreshold;
  if (three == null || two == null) return null;
  return '★★ ≤ $two · ★★★ ≤ $three';
}

/// 클리어 화면 사용량 대비 3성 임계 1줄 ("잉크 182 사용 · ★★★ ≤ 156"). 미검증이면 사용량만.
String clearUsageLine(Level level, int inkUsed) {
  final three = levelStarInfo(level).threeStarThreshold;
  if (three == null) return '잉크 $inkUsed 사용';
  return '잉크 $inkUsed 사용 · ★★★ ≤ $three';
}

/// 고정 안내 문구 (기능 문구=명사형, 알림=서술). 어미 톤 3분할 규칙은 파일 헤더 참조.
abstract final class OnboardingCopy {
  static const String strokeGuide = '화면에 선을 그어 길 만들기';
  static const String gravityGuide = '버튼으로 중력 뒤집기';
  static const String starExplain = '잉크를 아낄수록 별을 더 받는다';
}
