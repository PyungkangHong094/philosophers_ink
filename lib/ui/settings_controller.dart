/// 셸 설정 상태 (reduced motion·햅틱·사운드). 영속화는 [ProgressStore] 경유.
///
/// reduced motion·햅틱 오프는 GDD 8.4.7 품질 바닥의 필수 대응. 사운드 토글은 M5 훅 지점.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../meta/progress_store.dart';

class SettingsController extends ChangeNotifier {
  final ProgressStore _store;

  bool _reducedMotion;
  bool _haptics;
  bool _sound;

  SettingsController(this._store, Map<String, dynamic> initial)
      : _reducedMotion = initial['reducedMotion'] == true,
        _haptics = initial['haptics'] != false, // 기본 on
        _sound = initial['sound'] != false; // 기본 on (M5 훅)

  factory SettingsController.fromStore(ProgressStore store) =>
      SettingsController(store, store.loadSettings());

  /// 설정 기반 reduced motion. 화면은 이 값과 MediaQuery.disableAnimations를 OR로 합친다.
  bool get reducedMotion => _reducedMotion;
  bool get haptics => _haptics;
  bool get sound => _sound;

  set reducedMotion(bool v) => _set(() => _reducedMotion = v);
  set haptics(bool v) => _set(() => _haptics = v);
  set sound(bool v) => _set(() => _sound = v);

  void _set(VoidCallback change) {
    change();
    _store.saveSettings({
      'reducedMotion': _reducedMotion,
      'haptics': _haptics,
      'sound': _sound,
    });
    notifyListeners();
  }

  /// 햅틱 게이트 — 설정이 켜져 있을 때만 실제 진동. (사운드 훅은 M5 sim-engineer 협의.)
  void hapticLight() {
    if (_haptics) HapticFeedback.lightImpact();
  }

  void hapticSelection() {
    if (_haptics) HapticFeedback.selectionClick();
  }
}
