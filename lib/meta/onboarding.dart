/// 온보딩 노출 이력 (GDD 7.2) — 1회성 안내를 본 적 있는지 추적·영속한다.
///
/// 목표 배너는 매 레벨 공통(비영속)이지만, 첫 조작 가이드·별점 설명·게이지 힌트는 1회만
/// 노출한다. 재플레이 시 반복 노출 금지. 설정의 "안내 다시 보기"가 [reset]으로 초기화한다.
library;

import 'package:flutter/foundation.dart';

/// 1회성 안내 키 (매직 스트링 단일 소스).
abstract final class OnboardingKey {
  static const String stroke = 'stroke'; // 첫 스트로크 가이드
  static const String gravity = 'gravity'; // 중력 반전 가이드
  static const String firstClear = 'firstClear'; // 첫 클리어 별점 설명
  static const String gauge = 'gauge'; // 잉크 게이지 힌트
}

class OnboardingState extends ChangeNotifier {
  final Set<String> _seen;

  /// 변경 시 호출 (영속화 훅).
  final void Function(OnboardingState state)? onChanged;

  OnboardingState({Set<String>? seen, this.onChanged})
      : _seen = {...?seen};

  bool hasSeen(String key) => _seen.contains(key);

  /// 처음 보는 키면 기록하고 true(=지금 노출) 반환. 이미 봤으면 false.
  bool markSeenOnce(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    onChanged?.call(this);
    notifyListeners();
    return true;
  }

  /// 전체 초기화 (안내 다시 보기).
  void reset() {
    if (_seen.isEmpty) return;
    _seen.clear();
    onChanged?.call(this);
    notifyListeners();
  }

  List<String> toJsonList() => _seen.toList()..sort();

  factory OnboardingState.fromJsonList(
    List<dynamic>? raw, {
    void Function(OnboardingState)? onChanged,
  }) =>
      OnboardingState(
        seen: {for (final e in raw ?? const []) '$e'},
        onChanged: onChanged,
      );
}
