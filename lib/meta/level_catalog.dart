/// 레벨 카탈로그 — assets/levels/ 를 스캔해 실제 존재하는 레벨만 노출한다 (GDD 10.6).
///
/// level-designer들이 파일을 점진적으로 추가하므로, 아직 없는 레벨 파일에 견고해야 한다:
/// AssetManifest에서 `assets/levels/level_*.json`을 찾아 파싱을 시도하고, 성공한 것만
/// 카탈로그에 담는다. 파싱 실패는 조용히 삼키지 않고 [loadErrors]에 남긴다(디버그 노출용).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, AssetManifest, rootBundle;

import '../level/level_model.dart';
import '../level/loader.dart';
import 'chapters.dart';

/// 카탈로그의 레벨 1개 — 메타 + 파싱된 [Level](플레이·별점 표시에 사용).
class LevelEntry {
  final int id;
  final int chapter;
  final String name;
  final String assetPath;
  final Level level;

  const LevelEntry({
    required this.id,
    required this.chapter,
    required this.name,
    required this.assetPath,
    required this.level,
  });

  /// 이 레벨이 작업(OPERATIO) 레벨인가 (골드 링).
  bool get isOperatio => isOperatioLevel(id);
}

/// 존재하는 레벨 전체의 인덱스. id 오름차순 정렬을 보장한다.
class LevelCatalog {
  final List<LevelEntry> entries;

  /// 스캔 중 파싱에 실패한 (경로, 사유) 목록.
  final List<String> loadErrors;

  LevelCatalog(List<LevelEntry> entries, {this.loadErrors = const []})
      : entries = List.unmodifiable(
          [...entries]..sort((a, b) => a.id.compareTo(b.id)),
        );

  LevelEntry? byId(int id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 해당 챕터에 존재하는 레벨 (id 오름차순).
  List<LevelEntry> entriesInChapter(int chapter) =>
      entries.where((e) => e.chapter == chapter).toList(growable: false);

  /// 콘텐츠가 하나라도 존재하는 챕터만 (챕터 선택에서 완전 빈 챕터도 골격은 노출하되
  /// 진행 계산은 이 목록 기준). ChapterInfo 순서 유지.
  List<ChapterInfo> get populatedChapters =>
      kChapters.where((c) => entriesInChapter(c.number).isNotEmpty).toList();

  /// AssetManifest를 읽어 assets/levels/ 아래 레벨을 발견·파싱한다.
  /// 매니페스트 로드 자체가 실패해도(테스트 환경 등) 빈 카탈로그로 폴백한다.
  static Future<LevelCatalog> discover({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final List<String> paths;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(b);
      paths = manifest
          .listAssets()
          .where((p) =>
              p.startsWith('assets/levels/') && p.endsWith('.json'))
          .toList()
        ..sort();
    } catch (e) {
      if (kDebugMode) debugPrint('[LevelCatalog] 매니페스트 로드 실패: $e');
      return LevelCatalog(const [], loadErrors: ['manifest: $e']);
    }

    final entries = <LevelEntry>[];
    final errors = <String>[];
    for (final path in paths) {
      try {
        final text = await b.loadString(path);
        final level = loadLevelFromJson(text, source: path);
        entries.add(LevelEntry(
          id: level.meta.id,
          chapter: level.meta.chapter,
          name: level.meta.name,
          assetPath: path,
          level: level,
        ));
      } catch (e) {
        errors.add('$path: $e');
        if (kDebugMode) {
          debugPrint('[LevelCatalog] 스킵 $path — $e');
        }
      }
    }
    return LevelCatalog(entries, loadErrors: errors);
  }
}
