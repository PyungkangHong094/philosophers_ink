/// 레벨 파일 입출력 (레벨 랩 CLI 전용). dart:io — 앱 빌드 미포함.
library;

import 'dart:convert';
import 'dart:io';

import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

const String kDefaultLevelsDir = 'assets/levels';
const String kDefaultOutDir = 'tool/level_lab/out';

/// 파일 경로 → 검증된 [Level]. 실패 시 loader가 LevelException을 던진다.
Level loadLevelFile(String path) =>
    loadLevelFromJson(File(path).readAsStringSync(), source: path);

/// [dir]의 level_*.json 경로를 이름순으로.
List<String> allLevelPaths([String dir = kDefaultLevelsDir]) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    throw ArgumentError('레벨 디렉터리 없음: $dir');
  }
  final files = d
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => RegExp(r'level_\d+\.json$').hasMatch(p))
      .toList()
    ..sort();
  return files;
}

/// meta.chapter == [chapter]인 레벨 경로만. 로드해 필터한다.
List<String> levelPathsForChapter(int chapter,
    [String dir = kDefaultLevelsDir]) {
  final out = <String>[];
  for (final p in allLevelPaths(dir)) {
    if (loadLevelFile(p).meta.chapter == chapter) out.add(p);
  }
  return out;
}

/// 결과 JSON을 [kDefaultOutDir]/level_NNN.json 형태로 기록한다.
void writeResultJson(String outDir, int levelId, Map<String, dynamic> json) {
  final d = Directory(outDir);
  if (!d.existsSync()) d.createSync(recursive: true);
  final name = 'level_${levelId.toString().padLeft(3, '0')}.json';
  File('$outDir/$name').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json));
}
