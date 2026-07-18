/// 진행·설정 영속화 (shared_preferences). GDD 7 별점/해금 기록의 저장소.
///
/// [GameProgress]는 순수 로직, 이 파일은 JSON 문자열 ↔ SharedPreferences 브리지만 담당한다.
/// 저장 실패로 게임이 죽지 않도록 로드 실패는 빈 진행으로 폴백한다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';

class ProgressStore {
  static const String _progressKey = 'ink.progress.v1';
  static const String _settingsKey = 'ink.settings.v1';

  final SharedPreferences _prefs;
  ProgressStore(this._prefs);

  static Future<ProgressStore> open() async =>
      ProgressStore(await SharedPreferences.getInstance());

  /// 저장된 진행을 로드하고, 변경 시 자동 저장하는 [GameProgress]를 만든다.
  GameProgress loadProgress() {
    final raw = _prefs.getString(_progressKey);
    if (raw == null) {
      return GameProgress(onChanged: _saveProgress);
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return GameProgress.fromJson(j, onChanged: _saveProgress);
    } catch (e) {
      if (kDebugMode) debugPrint('[ProgressStore] 진행 로드 실패, 초기화: $e');
      return GameProgress(onChanged: _saveProgress);
    }
  }

  void _saveProgress(GameProgress p) {
    _prefs.setString(_progressKey, jsonEncode(p.toJson()));
  }

  /// 설정 맵 로드 (없으면 빈 맵).
  Map<String, dynamic> loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void saveSettings(Map<String, dynamic> settings) {
    _prefs.setString(_settingsKey, jsonEncode(settings));
  }
}
