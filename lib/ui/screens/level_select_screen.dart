/// 레벨 선택 화면 (GDD 8.4.4 레벨 선택) — 잉크 플러드 진입점.
///
/// 상단 라틴 챕터명 대형 + 한글 부제. 5열 그리드 셀(정방형 56px+). 클리어 셀 = 번호 parchment
/// + 하단 소형 골드 별. 현재 셀 = 골드 보더 + 글로우. 잠금 = text3. 작업(OPERATIO) 셀은 골드 링.
/// 셀 탭 → 탭 좌표 기점 잉크 플러드로 인게임 진입. 골드 요소: 현재 셀·획득 별·작업 링.
library;

import 'package:flutter/material.dart';

import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/progress.dart';
import '../app.dart';
import '../game/play_screen.dart';
import '../ink_flood.dart';
import '../tokens.dart';
import '../widgets.dart';

enum _CellState { cleared, current, unlocked, locked, absent }

class LevelSelectScreen extends StatelessWidget {
  final ChapterInfo chapter;
  const LevelSelectScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final services = InkServices.of(context);
    final progress = services.progress;
    final catalog = services.catalog;

    return Scaffold(
      backgroundColor: InkColor.black1,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) {
            final entries = catalog.entriesInChapter(chapter.number);
            final currentId = _currentLevelId(entries, progress, catalog);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      InkSpace.md, InkSpace.sm, InkSpace.md, 0),
                  child: Row(
                    children: [
                      _BackButton(),
                      const SizedBox(width: InkSpace.xs),
                      Container(
                          width: 3,
                          height: 44,
                          color: chapter.swatch),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      InkSpace.lg, InkSpace.md, InkSpace.lg, InkSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chapter.latin, style: InkText.displayL),
                      const SizedBox(height: InkSpace.xs),
                      Text('${chapter.korean} · ${chapter.subtitle}',
                          style: InkText.body),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(InkSpace.lg),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: InkSpace.md,
                      crossAxisSpacing: InkSpace.md,
                      childAspectRatio: 1,
                    ),
                    itemCount: chapter.slotCount,
                    itemBuilder: (context, i) {
                      final levelId = chapter.firstLevel + i;
                      final entry = catalog.byId(levelId);
                      final state = _stateFor(
                          levelId, entry, currentId, progress, catalog);
                      return _LevelCell(
                        levelId: levelId,
                        stars: entry == null ? 0 : progress.starsFor(levelId),
                        state: state,
                        operatio: isOperatioLevel(levelId),
                        onTapAt: (state == _CellState.absent ||
                                state == _CellState.locked ||
                                entry == null)
                            ? null
                            : (origin) =>
                                _launch(context, entry, origin, replace: false),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 현재 챕터에서 "현재" 레벨 = 해금된 첫 미클리어 레벨.
  int? _currentLevelId(
      List<LevelEntry> entries, GameProgress progress, LevelCatalog catalog) {
    for (final e in entries) {
      if (progress.isLevelUnlocked(e.id, catalog) &&
          !progress.isCleared(e.id)) {
        return e.id;
      }
    }
    return null;
  }

  _CellState _stateFor(int levelId, LevelEntry? entry, int? currentId,
      GameProgress progress, LevelCatalog catalog) {
    if (entry == null) return _CellState.absent;
    if (progress.isCleared(levelId)) return _CellState.cleared;
    if (!progress.isLevelUnlocked(levelId, catalog)) return _CellState.locked;
    if (levelId == currentId) return _CellState.current;
    return _CellState.unlocked;
  }

  /// 잉크 플러드로 인게임 진입. onNext는 같은 챕터 내 다음 레벨(있고 존재하면)로 이어붙인다.
  void _launch(BuildContext context, LevelEntry entry, Offset origin,
      {required bool replace}) {
    final services = InkServices.of(context);
    final reduced = services.settings.reducedMotion ||
        MediaQuery.of(context).disableAnimations;
    final navigator = Navigator.of(context);

    final next = _nextInChapter(entry, services.catalog);
    VoidCallback? onNext;
    if (next != null) {
      onNext = () {
        final size = MediaQuery.of(navigator.context).size;
        _launch(navigator.context, next, size.center(Offset.zero),
            replace: true);
      };
    }

    final route = inkFloodRoute<void>(
      origin: origin,
      reducedMotion: reduced,
      builder: (_) => PlayScreen(
        entry: entry,
        progress: services.progress,
        settings: services.settings,
        onNext: onNext,
      ),
    );
    if (replace) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  LevelEntry? _nextInChapter(LevelEntry entry, LevelCatalog catalog) {
    final entries = catalog.entriesInChapter(entry.chapter);
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx < 0 || idx + 1 >= entries.length) return null;
    return entries[idx + 1];
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '뒤로',
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: InkSpace.touchTarget,
            height: InkSpace.touchTarget,
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_back,
                color: InkColor.text2, size: 22),
          ),
        ),
      );
}

class _LevelCell extends StatelessWidget {
  final int levelId;
  final int stars;
  final _CellState state;
  final bool operatio;

  /// 탭 시 전역 좌표를 넘겨 호출 (플러드 기점). null이면 비활성.
  final void Function(Offset globalOrigin)? onTapAt;

  const _LevelCell({
    required this.levelId,
    required this.stars,
    required this.state,
    required this.operatio,
    required this.onTapAt,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _CellState.current;
    final isCleared = state == _CellState.cleared;
    final dim = state == _CellState.locked || state == _CellState.absent;

    // 작업 레벨은 골드 링(승인된 골드 예외). 현재 셀도 골드 보더.
    final borderColor = (operatio && !dim)
        ? InkColor.gold
        : (isCurrent ? InkColor.gold : InkColor.hairline);
    final borderWidth = (isCurrent || (operatio && !dim)) ? 2.0 : 1.0;

    final numberColor = dim
        ? InkColor.text3
        : (isCleared || isCurrent ? InkColor.parchment : InkColor.text2);

    Offset origin = Offset.zero;

    return Semantics(
      button: onTapAt != null,
      label: 'LV $levelId',
      enabled: onTapAt != null,
      child: GestureDetector(
        onTapDown: (d) => origin = d.globalPosition,
        onTap: onTapAt == null ? null : () => onTapAt!(origin),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: InkSpace.levelCell,
            minHeight: InkSpace.levelCell,
          ),
          decoration: BoxDecoration(
            color: InkColor.black2,
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(InkSpace.radius),
            boxShadow: isCurrent
                ? const [BoxShadow(color: InkColor.goldDeep, blurRadius: 10)]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$levelId',
                    style: InkText.displayM.copyWith(
                      fontSize: 20,
                      color: numberColor,
                    ),
                  ),
                  if (isCleared) ...[
                    const SizedBox(height: 2),
                    StarRow(filled: stars, size: 9),
                  ],
                ],
              ),
              if (state == _CellState.locked)
                const Positioned(
                  bottom: 4,
                  child: Icon(Icons.lock_outline,
                      size: 10, color: InkColor.text3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
