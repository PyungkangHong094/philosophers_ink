/// 챕터 메타데이터 (GDD 7.1 — 연금술 대업 4단계). 순수 데이터.
///
/// 셸의 챕터/레벨 선택 화면이 참조한다. 챕터 스와치는 셸에 허용되는 유일한 유채색이며,
/// 잉크 플러드 전환의 목표색으로도 쓰인다.
library;

import 'package:flutter/widgets.dart';

import '../ui/tokens.dart';

/// 챕터 1개의 정적 정보.
class ChapterInfo {
  final int number;

  /// 라틴 챕터명 (대문자 Display용).
  final String latin;

  /// 한글 챕터명.
  final String korean;

  /// 한글 부제 (드로잉의 문법 등).
  final String subtitle;

  /// 이 챕터가 포함하는 레벨 id 범위 (양끝 포함).
  final int firstLevel;
  final int lastLevel;

  /// 챕터 스와치 색 (스파인·플러드·별). GDD 7.1 팔레트.
  final Color swatch;

  const ChapterInfo({
    required this.number,
    required this.latin,
    required this.korean,
    required this.subtitle,
    required this.firstLevel,
    required this.lastLevel,
    required this.swatch,
  });

  /// 이 챕터에 이론상 속하는 레벨 수 (콘텐츠 존재 여부와 무관한 정원).
  int get slotCount => lastLevel - firstLevel + 1;

  bool contains(int levelId) => levelId >= firstLevel && levelId <= lastLevel;
}

/// 런칭 4챕터 정의 (77레벨). 레벨 파일이 아직 없어도 챕터 골격은 항상 존재한다.
const List<ChapterInfo> kChapters = [
  ChapterInfo(
    number: 1,
    latin: 'NIGREDO',
    korean: '니그레도',
    subtitle: '드로잉의 문법',
    firstLevel: 1,
    lastLevel: 11,
    swatch: InkColor.nigredo,
  ),
  ChapterInfo(
    number: 2,
    latin: 'ALBEDO',
    korean: '알베도',
    subtitle: '물과 서리',
    firstLevel: 12,
    lastLevel: 33,
    swatch: InkColor.albedo,
  ),
  ChapterInfo(
    number: 3,
    latin: 'CITRINITAS',
    korean: '키트리니타스',
    subtitle: '불과 증기',
    firstLevel: 34,
    lastLevel: 55,
    swatch: InkColor.citrinitas,
  ),
  ChapterInfo(
    number: 4,
    latin: 'RUBEDO',
    korean: '루베도',
    subtitle: '용암과 돌',
    firstLevel: 56,
    lastLevel: 77,
    swatch: InkColor.rubedo,
  ),
];

/// 레벨 id가 속한 챕터. 범위를 벗어나면 null.
ChapterInfo? chapterForLevel(int levelId) {
  for (final c in kChapters) {
    if (c.contains(levelId)) return c;
  }
  return null;
}

/// 작업(OPERATIO) 레벨 id — 11의 배수 (골드 링 표시, GDD 7.1 / LEVELS 5장).
bool isOperatioLevel(int levelId) => levelId > 0 && levelId % 11 == 0;
