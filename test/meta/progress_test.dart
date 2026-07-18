/// 메타 진행 단위 테스트 — 별점 최고치 유지·직렬화 왕복·해금 규칙 (GDD 7).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/meta/level_catalog.dart';
import 'package:philosophers_ink/meta/progress.dart';

/// 테스트용 최소 Level — 카탈로그 엔트리에 넣을 뼈대.
Level _level(int id, int chapter) => Level(
      meta: LevelMeta(id: id, name: 'L$id', chapter: chapter, difficulty: 1),
      background: 0xFF000000,
      emitters: const [],
      flasks: const [],
      inkBudget: const {InkType.chalk: 10},
    );

LevelEntry _entry(int id, int chapter) => LevelEntry(
      id: id,
      chapter: chapter,
      name: 'L$id',
      assetPath: 'assets/levels/level_$id.json',
      level: _level(id, chapter),
    );

void main() {
  group('GameProgress 기록', () {
    test('별점은 최고치를 유지한다 (하락 없음)', () {
      final p = GameProgress();
      p.record(1, cleared: true, stars: 2);
      expect(p.starsFor(1), 2);
      p.record(1, cleared: true, stars: 1); // 더 낮은 별점 재도전
      expect(p.starsFor(1), 2, reason: '최고 별점 유지');
      p.record(1, cleared: true, stars: 3);
      expect(p.starsFor(1), 3);
    });

    test('클리어 플래그는 한 번 켜지면 유지', () {
      final p = GameProgress();
      p.record(1, cleared: true, stars: 1);
      p.record(1, cleared: false, stars: 0);
      expect(p.isCleared(1), isTrue);
    });

    test('변화 없는 기록은 notify하지 않는다', () {
      final p = GameProgress();
      var notes = 0;
      p.addListener(() => notes++);
      p.record(1, cleared: true, stars: 2);
      expect(notes, 1);
      p.record(1, cleared: true, stars: 2); // 동일
      expect(notes, 1, reason: '중복 기록은 notify 없음');
    });

    test('onChanged 훅이 변경마다 호출된다 (영속화)', () {
      var saves = 0;
      final p = GameProgress(onChanged: (_) => saves++);
      p.record(1, cleared: true, stars: 1);
      p.record(2, cleared: true, stars: 3);
      expect(saves, 2);
    });

    test('totalStars / starsInLevels 집계', () {
      final p = GameProgress();
      p.record(1, cleared: true, stars: 3);
      p.record(2, cleared: true, stars: 2);
      p.record(12, cleared: true, stars: 1);
      expect(p.totalStars, 6);
      expect(p.starsInLevels([1, 2]), 5);
      expect(p.clearedCountIn([1, 2, 3]), 2);
    });
  });

  group('직렬화 왕복', () {
    test('toJson → fromJson 이 기록을 보존한다', () {
      final p = GameProgress();
      p.record(1, cleared: true, stars: 3);
      p.record(5, cleared: true, stars: 1);
      final restored = GameProgress.fromJson(p.toJson());
      expect(restored.starsFor(1), 3);
      expect(restored.starsFor(5), 1);
      expect(restored.isCleared(1), isTrue);
      expect(restored.totalStars, 4);
    });

    test('깨진/누락 JSON은 빈 진행으로 폴백', () {
      final restored = GameProgress.fromJson({'records': 'garbage'});
      expect(restored.totalStars, 0);
    });
  });

  group('해금 규칙', () {
    // 챕터 1: 레벨 1,2,3 / 챕터 2: 레벨 12,13.
    final catalog = LevelCatalog([
      _entry(1, 1),
      _entry(2, 1),
      _entry(3, 1),
      _entry(12, 2),
      _entry(13, 2),
    ]);

    test('첫 챕터는 항상 해금, 첫 레벨도 해금', () {
      final p = GameProgress();
      expect(p.isChapterUnlocked(1, catalog), isTrue);
      expect(p.isLevelUnlocked(1, catalog), isTrue);
    });

    test('챕터 내부는 선형 — 직전 레벨 클리어해야 다음이 열린다', () {
      final p = GameProgress();
      expect(p.isLevelUnlocked(2, catalog), isFalse);
      p.record(1, cleared: true, stars: 1);
      expect(p.isLevelUnlocked(2, catalog), isTrue);
      expect(p.isLevelUnlocked(3, catalog), isFalse);
    });

    test('챕터 2는 챕터 1 전부 클리어해야 해금', () {
      final p = GameProgress();
      expect(p.isChapterUnlocked(2, catalog), isFalse);
      p.record(1, cleared: true, stars: 1);
      p.record(2, cleared: true, stars: 1);
      expect(p.isChapterUnlocked(2, catalog), isFalse, reason: '3 미클리어');
      p.record(3, cleared: true, stars: 1);
      expect(p.isChapterUnlocked(2, catalog), isTrue);
      expect(p.isLevelUnlocked(12, catalog), isTrue);
      expect(p.isLevelUnlocked(13, catalog), isFalse);
    });

    test('존재하지 않는 레벨은 해금 아님', () {
      final p = GameProgress();
      expect(p.isLevelUnlocked(999, catalog), isFalse);
    });
  });
}
