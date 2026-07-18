/// 메타 진행 상태 — 레벨별 클리어·최고 별점 + 해금 규칙 (GDD 7). 영속화는 [ProgressStore].
///
/// 순수 로직(직렬화·해금 판정)만 담아 단위 테스트 대상이 된다. 영속 I/O는 분리한다.
/// 해금 규칙(GDD 7.1 "N장 완료 시 해금", 챕터 경계 11의 배수):
///  - 챕터 1은 항상 해금. 챕터 c(>1)는 하위 챕터의 **존재하는 모든 레벨**을 클리어하면 해금.
///  - 챕터 내부는 선형 해금: 챕터 첫 레벨은 챕터 해금 시 열리고, 이후 레벨은 직전(존재하는)
///    레벨을 클리어하면 열린다. 콘텐츠가 듬성듬성해도(파일 일부만 존재) 안전하게 동작한다.
library;

import 'package:flutter/foundation.dart';

import 'level_catalog.dart';

/// 레벨 1개의 기록.
class LevelRecord {
  final bool cleared;

  /// 최고 별점 0~3 (미클리어면 0).
  final int stars;

  const LevelRecord({required this.cleared, required this.stars});

  Map<String, dynamic> toJson() => {'cleared': cleared, 'stars': stars};

  factory LevelRecord.fromJson(Map<String, dynamic> j) => LevelRecord(
        cleared: j['cleared'] == true,
        stars: (j['stars'] as num?)?.toInt() ?? 0,
      );
}

/// 전체 진행. ChangeNotifier로 셸 화면이 별점·해금 변화를 구독한다.
class GameProgress extends ChangeNotifier {
  final Map<int, LevelRecord> _records;

  /// 기록 변경 시 호출 (영속화 훅). 테스트에서는 생략.
  final void Function(GameProgress progress)? onChanged;

  GameProgress({Map<int, LevelRecord>? records, this.onChanged})
      : _records = {...?records};

  /// 이 레벨의 기록 (없으면 미클리어 0성).
  LevelRecord recordFor(int id) =>
      _records[id] ?? const LevelRecord(cleared: false, stars: 0);

  bool isCleared(int id) => _records[id]?.cleared ?? false;

  int starsFor(int id) => _records[id]?.stars ?? 0;

  /// 전체 획득 별 합.
  int get totalStars =>
      _records.values.fold<int>(0, (a, r) => a + r.stars);

  /// 특정 레벨 집합의 별 합 (챕터 진행도 표시).
  int starsInLevels(Iterable<int> ids) =>
      ids.fold<int>(0, (a, id) => a + starsFor(id));

  /// 클리어한 레벨 수 (특정 집합 내).
  int clearedCountIn(Iterable<int> ids) =>
      ids.where(isCleared).length;

  /// 결과 기록. 별점은 항상 최고치를 유지(하락 없음). 실제 변화 시에만 notify + 영속.
  void record(int id, {required bool cleared, required int stars}) {
    final prev = _records[id];
    final newStars = stars > (prev?.stars ?? 0) ? stars : (prev?.stars ?? 0);
    final newCleared = cleared || (prev?.cleared ?? false);
    if (prev != null &&
        prev.cleared == newCleared &&
        prev.stars == newStars) {
      return; // 변화 없음.
    }
    _records[id] = LevelRecord(cleared: newCleared, stars: newStars);
    onChanged?.call(this);
    notifyListeners();
  }

  // ---- 해금 규칙 (카탈로그 기준) ----

  /// 챕터 해금 여부. 첫 (콘텐츠 존재) 챕터는 항상 해금.
  bool isChapterUnlocked(int chapter, LevelCatalog catalog) {
    final populated = catalog.populatedChapters;
    if (populated.isEmpty) return false;
    if (chapter <= populated.first.number) return true;
    // 하위 챕터의 존재하는 모든 레벨을 클리어했는가.
    for (final c in populated) {
      if (c.number >= chapter) break;
      final ids = catalog.entriesInChapter(c.number).map((e) => e.id);
      if (ids.any((id) => !isCleared(id))) return false;
    }
    return true;
  }

  /// 레벨 해금 여부. 챕터가 해금돼야 하고, 챕터 내부 선형 해금을 만족해야 한다.
  bool isLevelUnlocked(int id, LevelCatalog catalog) {
    final entry = catalog.byId(id);
    if (entry == null) return false;
    if (!isChapterUnlocked(entry.chapter, catalog)) return false;
    final chapterEntries = catalog.entriesInChapter(entry.chapter);
    final idx = chapterEntries.indexWhere((e) => e.id == id);
    if (idx <= 0) return true; // 챕터 첫 레벨.
    return isCleared(chapterEntries[idx - 1].id);
  }

  // ---- 직렬화 ----

  Map<String, dynamic> toJson() => {
        'version': 1,
        'records': {
          for (final e in _records.entries) '${e.key}': e.value.toJson(),
        },
      };

  factory GameProgress.fromJson(
    Map<String, dynamic> j, {
    void Function(GameProgress)? onChanged,
  }) {
    final out = <int, LevelRecord>{};
    final raw = j['records'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null && v is Map) {
          out[id] = LevelRecord.fromJson(v.cast<String, dynamic>());
        }
      });
    }
    return GameProgress(records: out, onChanged: onChanged);
  }
}
