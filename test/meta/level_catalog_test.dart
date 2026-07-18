/// 레벨 카탈로그 단위 테스트 — id 정렬·챕터 그룹핑·populatedChapters.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';

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
  test('엔트리는 id 오름차순으로 정렬된다', () {
    final c = LevelCatalog([_entry(3, 1), _entry(1, 1), _entry(2, 1)]);
    expect(c.entries.map((e) => e.id), [1, 2, 3]);
  });

  test('byId / entriesInChapter', () {
    final c = LevelCatalog([_entry(1, 1), _entry(12, 2), _entry(13, 2)]);
    expect(c.byId(12)?.name, 'L12');
    expect(c.byId(99), isNull);
    expect(c.entriesInChapter(2).map((e) => e.id), [12, 13]);
    expect(c.entriesInChapter(3), isEmpty);
  });

  test('populatedChapters는 콘텐츠 있는 챕터만 (순서 유지)', () {
    final c = LevelCatalog([_entry(1, 1), _entry(34, 3)]);
    expect(c.populatedChapters.map((ch) => ch.number), [1, 3]);
  });

  test('빈 카탈로그도 안전', () {
    final c = LevelCatalog(const []);
    expect(c.entries, isEmpty);
    expect(c.populatedChapters, isEmpty);
    expect(c.byId(1), isNull);
  });
}
