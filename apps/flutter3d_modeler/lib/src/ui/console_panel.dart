/// `ux-26`'s own panel: everything said this session, newest first.
///
/// **Newest first, which is the opposite of the log's own order.** A log is
/// written oldest-first because that is the order things happened in; a
/// person opening this wants the thing that just happened, and scrolling to
/// the bottom of a list to find it is the one interaction a console must not
/// ask for. The list underneath is unchanged — `ConsoleLog` stays in the
/// order an agent replaying it needs.
library;

import 'package:flutter/material.dart';

import '../console_log.dart';
import 'theme.dart';

/// The filter across the top: everybody, or one of the two.
///
/// A nullable [ConsoleAuthor] rather than a three-valued enum of its own —
/// "all" is the absence of a filter, and `ConsoleLog.by` already takes null
/// to mean it.
class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.log, this.onClose});

  final ConsoleLog log;

  /// Closes the panel. Null draws no close button, for a caller that shows
  /// this somewhere with no place to put one.
  final VoidCallback? onClose;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  ConsoleAuthor? _only;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ConsoleEntry> shown = widget.log.by(_only).reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 0, label: Text('All')),
                    ButtonSegment<int>(value: 1, label: Text('You')),
                    ButtonSegment<int>(value: 2, label: Text('Agent')),
                  ],
                  selected: <int>{
                    switch (_only) {
                      null => 0,
                      ConsoleAuthor.person => 1,
                      ConsoleAuthor.agent => 2,
                    },
                  },
                  onSelectionChanged: (Set<int> picked) => setState(() {
                    _only = switch (picked.first) {
                      1 => ConsoleAuthor.person,
                      2 => ConsoleAuthor.agent,
                      _ => null,
                    };
                  }),
                ),
              ),
              if (widget.onClose case final VoidCallback close) ...<Widget>[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close the console',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: close,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    _only == null
                        ? 'nothing has been said yet'
                        : 'nothing from ${_only!.label.toLowerCase()} yet',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int at) =>
                      _Line(entry: shown[at]),
                ),
        ),
      ],
    );
  }
}

/// One entry: the time, who said it, and what.
class _Line extends StatelessWidget {
  const _Line({required this.entry});

  final ConsoleEntry entry;

  /// `14:03:22` — seconds included, because two refusals a second apart is
  /// the case a person is trying to tell apart when they come here at all.
  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // The same three levels the status line paints, for the same reason: a
    // refusal has to be the one line somebody notices.
    final Color colour = switch (entry.kind) {
      ConsoleKind.report => theme.colorScheme.onSurface,
      ConsoleKind.warning => theme.colorScheme.tertiary,
      ConsoleKind.refusal => theme.colorScheme.error,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 58,
            child: Text(
              _clock(entry.at),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              entry.author.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: entry.author == ConsoleAuthor.agent
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.tool == null ? entry.text : '${entry.tool}: ${entry.text}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colour,
                fontWeight: entry.kind == ConsoleKind.refusal
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How tall the console sits under the viewport — `ux-26`. Eight rows and a
/// filter, which is what fits without taking the picture apart.
const double kConsoleHeight = ModelerMetrics.timelineRows;
