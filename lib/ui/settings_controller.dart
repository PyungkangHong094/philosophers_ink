/// 셸 설정 상태 (reduced motion·햅틱·사운드·볼륨). 영속화는 [ProgressStore] 경유.
///
/// reduced motion·햅틱 오프는 GDD 8.4.7 품질 바닥의 필수 대응. 사운드 토글·볼륨은 GDD 9
/// (음소거 토글 필수). 오디오 반영은 앱 루트가 이 컨트롤러를 구독해 [AudioService]에 전달한다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../meta/progress_store.dart';

class SettingsController extends ChangeNotifier {
  final ProgressStore _store;

  bool _reducedMotion;
  bool _haptics;
  bool _sound;
  double _volume;

  SettingsController(this._store, Map<String, dynamic> initial)
      : _reducedMotion = initial['reducedMotion'] == true,
        _haptics = initial['haptics'] != false, // 기본 on
        _sound = initial['sound'] != false, // 기본 on
        _volume = ((initial['volume'] as num?)?.toDouble() ?? 0.8)
            .clamp(0.0, 1.0);
  // BGM 설정 키 폐기 (절차 패드 제거) — 저장된 bgm 값은 더 이상 읽지 않는다.

  factory SettingsController.fromStore(ProgressStore store) =>
      SettingsController(store, store.loadSettings());

  /// 설정 기반 reduced motion. 화면은 이 값과 MediaQuery.disableAnimations를 OR로 합친다.
  bool get reducedMotion => _reducedMotion;
  bool get haptics => _haptics;
  bool get sound => _sound;

  /// 마스터 볼륨 0~1.
  double get volume => _volume;

  set reducedMotion(bool v) => _set(() => _reducedMotion = v);
  set haptics(bool v) => _set(() => _haptics = v);
  set sound(bool v) => _set(() => _sound = v);
  set volume(double v) => _set(() => _volume = v.clamp(0.0, 1.0));

  void _set(VoidCallback change) {
    change();
    _store.saveSettings({
      'reducedMotion': _reducedMotion,
      'haptics': _haptics,
      'sound': _sound,
      'volume': _volume,
    });
    notifyListeners();
  }

  /// 햅틱 게이트 — 설정이 켜져 있을 때만 실제 진동.
  void hapticLight() {
    if (_haptics) HapticFeedback.lightImpact();
  }

  void hapticSelection() {
    if (_haptics) HapticFeedback.selectionClick();
  }
}
