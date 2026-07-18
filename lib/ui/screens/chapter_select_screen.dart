/// 챕터 선택 화면 (GDD 8.4.4 챕터 선택).
///
/// 세로 카드 4장. 카드 = black2 + 헤어라인 + 좌측 챕터색 스파인. 라틴 챕터명 대형 + 한글명·
/// 레벨 범위 + 우측 진행도(별 tabular). 잠금 카드는 text3 + "N장 완료 시 해금". 현재 챕터는
/// 골드 보더. 골드 요소: 별 카운트 + 현재 챕터 보더.
library;

import 'package:flutter/material.dart';

import '../../meta/chapters.dart';
import '../../meta/level_catalog.dart';
import '../../meta/progress.dart';
import '../app.dart';
import '../tokens.dart';
import '../widgets.dart';
import 'level_select_screen.dart';
import 'settings_screen.dart';

class ChapterSelectScreen extends StatelessWidget {
  const ChapterSelectScreen({super.key});

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
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    InkSpace.lg, InkSpace.lg, InkSpace.md, InkSpace.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const InkEyebrow('MAGNUM OPUS'),
                          const SizedBox(height: InkSpace.xs),
                          Text('대업', style: InkText.titleKo),
                        ],
                      ),
                    ),
                    _SettingsButton(),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      InkSpace.lg, InkSpace.sm, InkSpace.lg, InkSpace.lg),
                  children: [
                    for (final chapter in kChapters)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: InkSpace.md),
                        child: _ChapterCard(
                          chapter: chapter,
                          progress: progress,
                          catalog: catalog,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '설정',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: InkSpace.touchTarget,
          height: InkSpace.touchTarget,
          alignment: Alignment.center,
          child: const Icon(Icons.settings_outlined,
              color: InkColor.text2, size: 22),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final ChapterInfo chapter;
  final GameProgress progress;
  final LevelCatalog catalog;

  const _ChapterCard({
    required this.chapter,
    required this.progress,
    required this.catalog,
  });

  @override
  Widget build(BuildContext context) {
    final entries = catalog.entriesInChapter(chapter.number);
    final ids = entries.map((e) => e.id);
    final unlocked = progress.isChapterUnlocked(chapter.number, catalog);
    final hasContent = entries.isNotEmpty;
    final stars = progress.starsInLevels(ids);
    final maxStars = entries.length * 3;
    final cleared = progress.clearedCountIn(ids);

    // 현재 챕터 = 해금됐고 아직 전부 클리어하지 않은 첫 챕터.
    final isCurrent = unlocked &&
        hasContent &&
        cleared < entries.length &&
        _isFirstIncomplete(chapter.number);

    final enabled = unlocked && hasContent;

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: InkCard(
        spine: chapter.swatch,
        highlighted: isCurrent,
        padding: const EdgeInsets.fromLTRB(
            InkSpace.lg, InkSpace.md, InkSpace.md, InkSpace.md),
        onTap: enabled
            ? () {
                final s = InkServices.of(context);
                s.settings.hapticSelection();
                s.audio.uiTap();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LevelSelectScreen(chapter: chapter),
                  ),
                );
              }
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.latin,
                    style: InkText.displayL.copyWith(
                      color: enabled ? InkColor.parchment : InkColor.text3,
                      fontSize: 34,
                    ),
                  ),
                  const SizedBox(height: InkSpace.xs),
                  Text(
                    '${chapter.korean} · ${chapter.subtitle}',
                    style: InkText.caption,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasContent
                        ? 'LV ${chapter.firstLevel}–${chapter.lastLevel} · ${entries.length}개 수록'
                        : '준비 중',
                    style: InkText.caption.copyWith(color: InkColor.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: InkSpace.md),
            if (!unlocked)
              _LockLabel(chapter: chapter)
            else if (hasContent)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(Icons.star, color: InkColor.gold, size: 16),
                  const SizedBox(height: InkSpace.xs),
                  Text('$stars / $maxStars', style: InkText.caption),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _isFirstIncomplete(int chapterNumber) {
    for (final c in catalog.populatedChapters) {
      final entries = catalog.entriesInChapter(c.number);
      final done = progress.clearedCountIn(entries.map((e) => e.id));
      if (done < entries.length) return c.number == chapterNumber;
    }
    return false;
  }
}

class _LockLabel extends StatelessWidget {
  final ChapterInfo chapter;
  const _LockLabel({required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Icon(Icons.lock_outline, color: InkColor.text3, size: 16),
        const SizedBox(height: InkSpace.xs),
        SizedBox(
          width: 96,
          child: Text(
            '${chapter.number - 1}장 완료 시 해금',
            textAlign: TextAlign.end,
            style: InkText.caption.copyWith(color: InkColor.text3),
          ),
        ),
      ],
    );
  }
}
