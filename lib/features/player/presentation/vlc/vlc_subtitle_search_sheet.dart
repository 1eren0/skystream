import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:vlc_player/vlc_player.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../domain/entity/subtitle_model.dart';
import '../../domain/subtitle_search_target.dart';
import '../subtitle_search_provider.dart';
import '../widgets/hotstar_player_style.dart';

/// The door onto [SubtitleSearch]: online subtitle search for what is playing.
///
/// The sheet is handed a [SubtitleSearchTarget] — the title the player is
/// showing and, when the catalogue knew them, its IMDb/TMDb id and the episode.
/// With an id it searches the moment it opens, because an id match is exact and
/// a title match is a guess. The field shows the title, and the moment the
/// viewer edits it the next search is by that text alone: every provider
/// prefers an id over the query when both are sent, so an edited title with the
/// ids still attached would be silently ignored. Restoring the exact title
/// turns the ids back on.
///
/// A downloaded result goes to [onFile] - the Subtitles tab lists it and puts
/// it on screen - or, with no [onFile], to the engine as an ordinary side-car.
///
/// Full screen, in the shape the search had before the player moved to
/// libVLC: a search field, a row of languages, and one card per result. Every
/// control is a focus stop with a ring a remote can see - the field, its
/// buttons, each language, each result - and every one of them also answers a
/// tap, a click and the keyboard.
class VlcSubtitleSearchSheet extends ConsumerStatefulWidget {
  const VlcSubtitleSearchSheet({
    required this.controller,
    this.target,
    this.isTv = false,
    this.onFile,
    super.key,
  });

  final VlcPlayerController controller;

  /// Takes a downloaded result, as a file on this device, and says whether it
  /// could be used. Null hands the file to [controller] instead.
  final Future<bool> Function(Uri file, OnlineSubtitle subtitle)? onFile;

  /// What the player already knows the viewer is watching. The title seeds
  /// the field; an id, when there is one, makes the search fire on open.
  final SubtitleSearchTarget? target;

  /// On a D-pad, focus starts on the search button when the field is seeded and
  /// on the field itself when there is nothing to search for yet.
  final bool isTv;

  /// Resolves to `true` when a subtitle was added, so the caller can close
  /// itself instead of dropping the viewer back into a stale track list.
  static Future<bool?> show(
    BuildContext context,
    VlcPlayerController controller, {
    SubtitleSearchTarget? target,
    bool isTv = false,
    Future<bool> Function(Uri file, OnlineSubtitle subtitle)? onFile,
  }) {
    return showDialog<bool>(
      context: context,
      useSafeArea: false,
      barrierColor: HotstarPlayerStyle.background,
      builder: (_) => VlcSubtitleSearchSheet(
        controller: controller,
        target: target,
        isTv: isTv,
        onFile: onFile,
      ),
    );
  }

  @override
  ConsumerState<VlcSubtitleSearchSheet> createState() =>
      _VlcSubtitleSearchSheetState();
}

class _VlcSubtitleSearchSheetState
    extends ConsumerState<VlcSubtitleSearchSheet> {
  late final TextEditingController _query = TextEditingController(
    text: widget.target?.title ?? '',
  );
  final ScrollController _languageScroll = ScrollController();
  final FocusNode _fieldNode = FocusNode(debugLabel: 'subtitle search field');

  /// One node per language chip, for the life of the sheet: the row is
  /// entered on the one searched in, and a node never moves between chips -
  /// one that did would take focus with it.
  final Map<String, FocusNode> _languageNodes = {
    for (final code in subtitleLanguages.values)
      code: FocusNode(debugLabel: 'subtitle language $code'),
  };

  FocusNode? get _selectedLanguage =>
      _languageNodes[ref.read(subtitleLanguageProvider)];

  /// Whether the next search sends the target's ids. On while the field
  /// still reads the target's own title; off the moment it says anything
  /// else, so the viewer's words are what gets searched.
  bool _idSearch = false;

  /// The result being fetched and unpacked, while one is. Downloads take
  /// seconds over a slow link, and a second press would race the first.
  String? _downloadingId;
  String? _error;

  bool get _downloading => _downloadingId != null;

  @override
  void initState() {
    super.initState();
    _idSearch = widget.target?.hasId ?? false;
    // An id is worth a search nobody asked for; a bare title is not, or a local
    // file's filename would hit the network on every open. A search already in
    // flight (the notifier outlives this sheet) is left to finish.
    if (_idSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(subtitleSearchProvider).isLoading) return;
        _search();
      });
    }
    // The language searched in is in view from the start, not off the end of
    // the row.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealLanguage());
  }

  @override
  void dispose() {
    _query.dispose();
    _languageScroll.dispose();
    _fieldNode.dispose();
    for (final node in _languageNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onEdited(String text) {
    final target = widget.target;
    setState(() {
      _idSearch =
          target != null && target.hasId && text.trim() == target.title.trim();
    });
  }

  void _search() {
    final query = _query.text.trim();
    final target = widget.target;
    final byId = _idSearch && target != null;
    if (query.isEmpty && !byId) return;
    setState(() => _error = null);
    // Season and episode ride along in both modes: a title search for a
    // series is still a search for *this* episode's file.
    ref
        .read(subtitleSearchProvider.notifier)
        .search(
          query: query,
          imdbId: byId ? target.imdbId : null,
          tmdbId: byId ? target.tmdbId : null,
          season: target?.season,
          episode: target?.episode,
          language: ref.read(subtitleLanguageProvider),
        );
  }

  void _clear() {
    _query.clear();
    _onEdited('');
  }

  void _pickLanguage(String code) {
    if (code == ref.read(subtitleLanguageProvider)) return;
    ref.read(subtitleLanguageProvider.notifier).set(code);
    _search();
  }

  void _revealLanguage() {
    final context = _selectedLanguage?.context;
    if (!mounted || context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: HotstarPlayerStyle.fastMotionDuration,
    );
  }

  Future<void> _apply(OnlineSubtitle subtitle) async {
    // Every card stays pressable while one downloads - a card that went
    // disabled would drop a remote's focus out of the list - so the press is
    // what is refused.
    if (_downloading) return;
    setState(() {
      _downloadingId = subtitle.id;
      _error = null;
    });
    // The episode on screen, which picks the right file out of a season pack.
    final path = await ref
        .read(subtitleSearchProvider.notifier)
        .downloadAndPrepare(
          subtitle,
          season: widget.target?.season,
          episode: widget.target?.episode,
        );
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _downloadingId = null;
        _error = AppLocalizations.of(context)!.subtitleDownloadFailed;
      });
      return;
    }
    // The engine refuses side-cars for reasons the sheet cannot see: a disposed
    // controller, a URI the platform will not take, an addSlave that comes back
    // false. Unguarded the throw escapes an unawaited `onTap` future and the
    // download never ends, leaving every result refusing presses.
    //
    // [VlcSubtitleSearchSheet.onFile] can say no as well: a file that
    // downloaded but will not read.
    var used = false;
    try {
      final onFile = widget.onFile;
      if (onFile != null) {
        used = await onFile(Uri.file(path), subtitle);
      } else {
        await widget.controller.addSubtitle(Uri.file(path));
        used = true;
      }
    } catch (_) {
      used = false;
    }
    if (!mounted) return;
    if (!used) {
      setState(() {
        _downloadingId = null;
        _error = AppLocalizations.of(context)!.subtitleDownloadFailed;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = ref.watch(subtitleLanguageProvider);
    final results = ref.watch(subtitleSearchProvider);
    // Read beside the state it describes: the notifier assigns the mode
    // before every state write, so the pair is always of the same pass.
    final mode = ref.watch(subtitleSearchProvider.notifier).lastMode;
    final seeded = _query.text.trim().isNotEmpty;
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final gutter = compact ? 20.0 : 48.0;

    return Dialog.fullscreen(
      backgroundColor: HotstarPlayerStyle.background,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, compact ? 8 : 18, gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, l10n, compact: compact),
              const Divider(color: HotstarPlayerStyle.divider, height: 20),
              _field(context, l10n, seeded: seeded),
              const SizedBox(height: 12),
              _languages(language),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFEF9A9A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(child: _results(l10n, results, mode)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
  }) {
    return Row(
      children: [
        // Down from here is the field below it. Left to the directional
        // search it lands on the languages instead: the field's focus area
        // starts after its search icon, outside this button's column.
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                event.logicalKey != LogicalKeyboardKey.arrowDown) {
              return KeyEventResult.ignored;
            }
            _fieldNode.requestFocus();
            return KeyEventResult.handled;
          },
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            color: HotstarPlayerStyle.secondaryText,
            iconSize: compact ? 28 : 34,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            style: _ringed,
          ),
        ),
        Expanded(
          child: Text(
            l10n.searchSubtitlesOnline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HotstarPlayerStyle.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        // Balances the back button, so the title sits in the middle.
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    AppLocalizations l10n, {
    required bool seeded,
  }) {
    // A single-line field has no use for up and down, and on a remote they
    // are the only way out of it.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        // ignoreTextFields: a plain DirectionalFocusIntent is a no-op while a
        // text field has focus, which is exactly where these are pressed.
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
          ignoreTextFields: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
          ignoreTextFields: false,
        ),
      },
      child: TextField(
        controller: _query,
        focusNode: _fieldNode,
        autofocus: widget.isTv && !seeded,
        textInputAction: TextInputAction.search,
        onChanged: _onEdited,
        onSubmitted: (_) => _search(),
        style: const TextStyle(
          color: HotstarPlayerStyle.primaryText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: l10n.searchSubtitleNameHint,
          hintStyle: const TextStyle(color: HotstarPlayerStyle.mutedText),
          prefixIcon: const Icon(
            Icons.search,
            color: HotstarPlayerStyle.secondaryText,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: HotstarPlayerStyle.focusRing,
              width: HotstarPlayerStyle.focusRingWidth,
            ),
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seeded)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  color: HotstarPlayerStyle.secondaryText,
                  tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                  style: _ringed,
                  onPressed: _clear,
                ),
              IconButton(
                icon: const Icon(Icons.search),
                color: HotstarPlayerStyle.primaryText,
                tooltip: l10n.search,
                autofocus: widget.isTv && seeded,
                style: _ringed,
                onPressed: _search,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// One chip per language, in a row that scrolls sideways - by swipe, by
  /// wheel and by the desktop arrows. Focus arriving from above or below lands
  /// on the language searched in, not on whichever chip happens to be nearest.
  Widget _languages(String selected) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (inRow) {
        final selected = _selectedLanguage;
        if (!inRow || selected == null || selected.hasFocus) return;
        selected.requestFocus();
      },
      child: SizedBox(
        height: 44,
        child: DesktopScrollWrapper(
          controller: _languageScroll,
          isCompact: true,
          child: SingleChildScrollView(
            controller: _languageScroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final MapEntry(key: name, value: code)
                    in subtitleLanguages.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _LanguageChip(
                      label: name,
                      selected: code == selected,
                      focusNode: _languageNodes[code],
                      onPressed: () => _pickLanguage(code),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(
    AppLocalizations l10n,
    AsyncValue<List<OnlineSubtitle>?> results,
    SubtitleSearchMode mode,
  ) {
    return switch (results) {
      AsyncLoading() => const _LoadingResults(),
      // The search reports per-provider failures through its own logging and
      // still resolves, so an error here is the provider list itself failing
      // to build - worth showing rather than swallowing.
      AsyncError(:final error) => _Empty(
        icon: Icons.error_outline_rounded,
        text: l10n.subtitleSearchFailed('$error'),
      ),
      AsyncData(value: null) => _Empty(
        icon: Icons.subtitles_rounded,
        text: l10n.subtitleSearchPrompt,
      ),
      // Empty is empty, not a missing account: OpenSubtitles runs on a
      // bundled key, so a fresh install really did search.
      AsyncData(value: final found) when found!.isEmpty => _Empty(
        icon: Icons.subtitles_off_rounded,
        text: l10n.noSubtitlesFoundTryAnother,
      ),
      AsyncData(value: final found) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // These are not what was asked for: the exact match missed and the
          // notifier widened the search on its own. Said once, above the
          // list, as text - not a stop a remote has to step over.
          if (_fallbackNote(l10n, mode) case final note?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                note,
                style: const TextStyle(
                  color: HotstarPlayerStyle.mutedText,
                  fontSize: 13,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: found!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final subtitle = found[index];
                return _ResultCard(
                  subtitle: subtitle,
                  busy: _downloadingId == subtitle.id,
                  dimmed: _downloading && _downloadingId != subtitle.id,
                  onPressed: () => _apply(subtitle),
                );
              },
            ),
          ),
        ],
      ),
    };
  }

  /// What to say above results the notifier widened to on its own, or null when
  /// they are what was asked for.
  ///
  /// The two widenings are different news and cannot share a string. An id that
  /// missed leaves title matches for this episode. The season pass is reachable
  /// with no id ever sent, and what matters there is that the list now spans
  /// the whole season, so the viewer has to find their own episode in it. An
  /// exhaustive switch, so a new mode cannot silently inherit either note.
  static String? _fallbackNote(
    AppLocalizations l10n,
    SubtitleSearchMode mode,
  ) => switch (mode) {
    SubtitleSearchMode.byId || SubtitleSearchMode.byTitle => null,
    SubtitleSearchMode.byTitleAfterIdMiss => l10n.subtitleSearchTitleFallback,
    SubtitleSearchMode.bySeasonAfterEpisodeMiss =>
      l10n.subtitleSearchSeasonFallback,
  };
}

/// A ring round an icon button while it holds focus, bright enough to find
/// from across a room.
final ButtonStyle _ringed = ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(
            color: HotstarPlayerStyle.focusRing,
            width: HotstarPlayerStyle.focusRingWidth,
          )
        : null,
  ),
);

/// A language to search in.
class _LanguageChip extends StatefulWidget {
  const _LanguageChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_LanguageChip> createState() => _LanguageChipState();
}

class _LanguageChipState extends State<_LanguageChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onPressed,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          // A remote moving along the row takes the row with it.
          if (focused) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: HotstarPlayerStyle.fastMotionDuration,
            );
          }
        },
        borderRadius: radius,
        child: AnimatedContainer(
          duration: HotstarPlayerStyle.fastMotionDuration,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? HotstarPlayerStyle.accent
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: radius,
            border: Border.all(
              color: _focused
                  ? HotstarPlayerStyle.focusRing
                  : Colors.transparent,
              width: HotstarPlayerStyle.focusRingWidth,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.selected
                  ? Colors.white
                  : HotstarPlayerStyle.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

/// One result: its release name, then the language badge in its provider's
/// colour, the provider, and whether it is for the hard of hearing.
class _ResultCard extends StatefulWidget {
  const _ResultCard({
    required this.subtitle,
    required this.busy,
    required this.dimmed,
    required this.onPressed,
  });

  final OnlineSubtitle subtitle;

  /// This result is the one downloading.
  final bool busy;

  /// Another result is downloading.
  final bool dimmed;
  final VoidCallback onPressed;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _focused = false;

  /// SubSource blue and OpenSubtitles orange, as they always were; the rest in
  /// the accent.
  Color get _providerColour {
    final source = widget.subtitle.source.toLowerCase();
    if (source.contains('subsource')) return Colors.blueAccent;
    if (source.contains('opensubtitles')) return Colors.orangeAccent;
    return HotstarPlayerStyle.accent;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    final colour = _providerColour;
    final radius = BorderRadius.circular(12);
    return AnimatedOpacity(
      duration: HotstarPlayerStyle.fastMotionDuration,
      opacity: widget.dimmed ? 0.45 : 1,
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onPressed,
          onFocusChange: (focused) => setState(() => _focused = focused),
          borderRadius: radius,
          child: AnimatedContainer(
            duration: HotstarPlayerStyle.fastMotionDuration,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: _focused
                    ? HotstarPlayerStyle.focusRing
                    : Colors.transparent,
                width: HotstarPlayerStyle.focusRingWidth,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HotstarPlayerStyle.primaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colour.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colour.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        subtitle.language.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: colour,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Takes the room, so the icons sit at the card's edge.
                    Expanded(
                      child: Text(
                        subtitle.source,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HotstarPlayerStyle.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (subtitle.isHearingImpaired)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: 'SDH',
                          child: Icon(
                            Icons.hearing,
                            size: 16,
                            color: HotstarPlayerStyle.mutedText,
                          ),
                        ),
                      ),
                    if (widget.busy)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.download_for_offline_outlined,
                        size: 20,
                        color: HotstarPlayerStyle.mutedText,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the results will be, while they load.
class _LoadingResults extends StatelessWidget {
  const _LoadingResults();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.2),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(220, 14),
              const SizedBox(height: 8),
              Row(
                children: [bar(60, 18), const SizedBox(width: 8), bar(80, 14)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A state with nothing to list: an icon and what to do next.
class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: HotstarPlayerStyle.mutedText),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: HotstarPlayerStyle.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
