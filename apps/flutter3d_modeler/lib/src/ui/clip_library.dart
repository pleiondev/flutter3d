/// Screen 14's own left column: a search box and a card per clip in the
/// imported source file — `anim-18`'s row, `ui/clip_library.dart` in the
/// plan's own words.
///
/// **The search query is local widget state, not lifted.** Nothing else
/// reads it and nothing on the document remembers it — the same "a view
/// concern with no undo of its own" `material_studio_dialog.dart`'s own
/// `_body`/`_presetIndex` already are, one layer down from this file.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../../l10n/app_localizations.dart';

/// [clip]'s own length, in seconds — the latest key any of its tracks
/// carries, or zero for a clip with no keys at all.
double clipDurationSeconds(ProjectClip clip) {
  var latest = 0.0;
  for (final ProjectTrack track in clip.tracks) {
    final times = track.track.times;
    if (times.isEmpty) continue;
    final last = times.last;
    if (last > latest) latest = last;
  }
  return latest;
}

/// The library column: a search box (radius 18) over a grid of clip cards
/// (34×34 icon, name, duration) — null [source] draws the "Import a source
/// clip" prompt instead of an empty list, since a library with nothing
/// imported yet is not the same thing as a file with no clips in it.
class ClipLibrary extends StatefulWidget {
  const ClipLibrary({
    super.key,
    required this.source,
    required this.selectedClipIndex,
    required this.onSelectClip,
    required this.onImport,
  });

  /// The file `retarget.import` last opened, or null before anything has
  /// been.
  final RetargetSource? source;

  /// Which of [RetargetSource.clips] is open in the two viewports below.
  final int? selectedClipIndex;
  final ValueChanged<int> onSelectClip;

  /// `retarget.import`'s own rail tool, reachable a second way from here —
  /// the same convenience every other sub-mode's panel already offers its
  /// own tools through a button beside the list.
  final VoidCallback onImport;

  @override
  State<ClipLibrary> createState() => _ClipLibraryState();
}

class _ClipLibraryState extends State<ClipLibrary> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final RetargetSource? source = widget.source;
    final List<ProjectClip> clips = source?.clips ?? const <ProjectClip>[];
    final String query = _query.trim().toLowerCase();
    final AppLocalizations l = AppLocalizations.of(context);
    final List<int> shown = <int>[
      for (var i = 0; i < clips.length; i++)
        if (query.isEmpty ||
            (clips[i].name ?? 'clip $i').toLowerCase().contains(query))
          i,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              enabled: source != null,
              onChanged: (String v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: l.clipSearch,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: OutlinedButton.icon(
              onPressed: widget.onImport,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: Text(
                source == null ? 'Import a source clip' : 'Import another',
              ),
            ),
          ),
          if (source?.warning case final String warning) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _WarningCard(text: warning),
            ),
          ],
          Expanded(
            child: source == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l.clipNoSource,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : shown.isEmpty
                ? Center(
                    child: Text(
                      l.clipNoMatch(_query),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    children: <Widget>[
                      for (final int i in shown)
                        _ClipCard(
                          name: clips[i].name ?? 'clip $i',
                          duration: clipDurationSeconds(clips[i]),
                          selected: i == widget.selectedClipIndex,
                          onTap: () => widget.onSelectClip(i),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One clip: a 34×34 icon, its name, and its own length in seconds.
class _ClipCard extends StatelessWidget {
  const _ClipCard({
    required this.name,
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final double duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.surfaceContainerHighest : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.directions_run_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${duration.toStringAsFixed(1)}s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
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

/// Screen 14's own "imported without a skin" card — `#3A2118`/`#FFB86B` in
/// the hand-off, read here off the theme's own `tertiaryContainer`/`tertiary`
/// roles the same way `scene_shadows_panel.dart`'s own warning text already
/// is, rather than the literal hex.
class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_outlined, size: 16, color: scheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.tertiary),
            ),
          ),
        ],
      ),
    );
  }
}
