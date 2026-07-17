# 패키지 선별 보고서 (2026-07-18)

입력: `~/Documents/작업/flutter_game_dev_packages.md` (게임 개발 패키지 후보 30여 종)
기준: 이 게임은 **CustomPainter + Uint8List 직접 렌더링** 기반 falling-sand 시뮬레이션.
게임 엔진(Flame)을 쓰지 않는 것이 아키텍처 SSOT(GDD 7장)다.

## 유지 (기설치)

| 패키지 | 용도 | 비고 |
|---|---|---|
| flutter_soloud | SFX/BGM (M5) | 게임용 저지연 오디오. 목록의 audioplayers/just_audio보다 지연 특성 우수 |
| flutter_animate | 셸 UI 애니메이션 (M4) | 목록의 animate_do·staggered_animations 역할 포괄 |
| shared_preferences | 별점·진행도 저장 | 목록 외 필수 |
| path_provider | 에디터 파일쓰기·세이브 | 백로그 항목 해소용 |

## 신규 추가

| 패키지 | 용도 | 근거 |
|---|---|---|
| animations | 셸 화면 전환 (컨테이너 트랜스폼 등) | M4 셸 1차에서 화면 전환 표준화 |

## 제외 (사유)

- **Flame / Bonfire / forge2d / flame_audio / flame_tiled** — 게임 엔진 미사용이 설계 결정.
  CA 시뮬은 자체 그리드 코어(lib/sim)가 담당하며 Flame 도입 시 렌더 파이프라인 전면 재작성 필요.
- **flutter_unity_widget / playing_cards / flutter_joystick / bonfire** — 장르 불일치.
- **lottie / rive** — 외부 애니메이션 에셋 없음. 모든 모션은 GDD 8.4 모션 토큰 기반 코드 구현.
- **just_audio / audioplayers / flutter_sound / audio_service / record** — flutter_soloud로 통일.
  백그라운드 재생·녹음은 퍼즐 게임 요구사항 아님.
- **getwidget / shadcn_ui / styled_widget / nb_utils** — 셸은 GDD 8.4 디자인 시스템(트루 블랙+골드)
  전용 커스텀 컴포넌트로 구현. 범용 UI 킷은 디자인 언어 충돌 + 앱 크기 증가.
- **flutter_shaders / mesh_gradient / animate_gradient / particles_flutter / animated_background** —
  잉크 플러드 전환·파티클은 기존 CustomPainter 역량으로 구현(렌더 코어와 동일 기술).
  M5 폴리시에서 셰이더가 실제 필요해지면 flutter_shaders만 재검토.
- **desktop_drop / super_drag_and_drop / gesture_x_detector / flutter_swipe_detector** —
  입력은 석필 드로잉(포인터 래스터라이즈) 단일 체계. 제스처 패키지 불필요.

## 이연 (M6 시점 설치)

- **google_mobile_ads**, **in_app_purchase** — 광고·IAP. 플랫폼별 네이티브 설정(AndroidManifest,
  Info.plist, 앱 ID) 필요하므로 M6에서 설치·구성.
- **games_services** — 리더보드·업적은 GDD 범위 확인 후 M6에서 결정.
