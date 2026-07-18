/// 챕터 팔레트·작업 레벨 테스트 — 챕터 3(금)·4(진홍) 스와치와 OPERATIO 판정 (GDD 7.1).
///
/// 레벨 34~77이 병렬 저작 중이라도 카탈로그가 챕터 3·4를 자동 그룹핑하는지 확인한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/chapters.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/ui/tokens.dart';

LevelEntry _entry(int id, int chapter) => LevelEntry(
      id: id,
      chapter: chapter,
      name: 'L$id',
      assetPath: 'assets/levels/level_$id.json',
      level: Level(
        meta: LevelMeta(id: id, name: 'L$id', chapter: chapter, difficulty: 1),
        background: 0xFF000000,
        emitters: const [],
        flasks: const [],
        inkBudget: const {InkType.chalk: 10},
      ),
    );

void main() {
  test('챕터 3·4 스와치가 토큰과 일치 (금·진홍)', () {
    final c3 = kChapters.firstWhere((c) => c.number == 3);
    final c4 = kChapters.firstWhere((c) => c.number == 4);
    expect(c3.swatch, InkColor.citrinitas);
    expect(c4.swatch, InkColor.rubedo);
    expect(c3.latin, 'CITRINITAS');
    expect(c4.latin, 'RUBEDO');
  });

  test('챕터 경계는 11의 배수 정렬', () {
    expect(kChapters.map((c) => c.firstLevel), [1, 12, 34, 56]);
    expect(kChapters.map((c) => c.lastLevel), [11, 33, 55, 77]);
  });

  test('OPERATIO 레벨 판정 (11의 배수)', () {
    for (final id in [11, 22, 33, 44, 55, 66, 77]) {
      expect(isOperatioLevel(id), isTrue, reason: 'LV $id');
    }
    for (final id in [1, 12, 34, 56, 76]) {
      expect(isOperatioLevel(id), isFalse, reason: 'LV $id');
    }
  });

  test('카탈로그가 챕터 3·4 레벨을 자동 그룹핑한다', () {
    final catalog = LevelCatalog([_entry(34, 3), _entry(56, 4), _entry(1, 1)]);
    expect(catalog.populatedChapters.map((c) => c.number), [1, 3, 4]);
    expect(catalog.entriesInChapter(3).single.id, 34);
    expect(catalog.entriesInChapter(4).single.id, 56);
  });
}
