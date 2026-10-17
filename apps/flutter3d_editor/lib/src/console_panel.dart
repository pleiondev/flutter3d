/// The bottom panel's console: what the editor said, what the game being
/// played printed, and what it posted.
///
/// **Three sources, one panel, and not merged into one list.** The editor's
/// own sentences carry a time; a game's console lines arrive from
/// `flutter run` or a VM service as text with no clock of the editor's on
/// them; and the events a game posts are numbered things an agent waits for
/// rather than lines anyone reads. Interleaving them would mean inventing an
/// order for two of the three, so each keeps its own and the panel switches
/// between them. What Play keeps — `PlayedGame.console` and
/// `PlayedGame.events` — is read here as it is, so this panel and the Play
/// screen show the same game the same way.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_play/attach.dart';

import 'editor_log.dart';

/// Which of the three the console shows.
enum ConsoleSource { editor, game, events }

final class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.log, required this.game});

  final EditorLog log;

  /// The game being played or attached to, or null when there is none.
  final PlayedGame? game;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  /// Which source is shown, and what the lines are filtered by: both the
  /// person's choice, so both are this panel's state.
  ConsoleSource _source = ConsoleSource.editor;
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _keeps(String line) {
    final wanted = _filter.text.trim().toLowerCase();
    return wanted.isEmpty || line.toLowerCase().contains(wanted);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: <Widget>[
              // The choices scroll and share the width with the filter, so a
              // bottom strip squeezed between two wide sides still shows
              // both rather than overflowing.
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final source in ConsoleSource.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: ValueKey<String>('console.${source.name}'),
                            label: Text(switch (source) {
                              ConsoleSource.editor => 'Editor',
                              ConsoleSource.game => 'Game',
                              ConsoleSource.events => 'Events',
                            }, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            selected: _source == source,
                            onSelected: (bool _) =>
                                setState(() => _source = source),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 200,
                    maxHeight: 28,
                  ),
                  child: TextField(
                    key: const ValueKey<String>('console.filter'),
                    controller: _filter,
                    style: TextStyle(color: scheme.onSurface, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Filter',
                      isDense: true,
                      prefixIcon: Icon(Icons.filter_list, size: 14),
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                    onChanged: (String _) => setState(() {}),
                  ),
                ),
              ),
              if (_source == ConsoleSource.editor)
                IconButton(
                  key: const ValueKey<String>('console.clear'),
                  tooltip: 'Clear the editor log',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: widget.log.clear,
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_source) {
            ConsoleSource.editor => ListenableBuilder(
              listenable: widget.log,
              builder: (BuildContext context, _) => _Lines(<_Line>[
                for (final entry in widget.log.entries)
                  if (_keeps(entry.text))
                    _Line(entry.text, prefix: entry.clock, error: entry.error),
              ]),
            ),
            ConsoleSource.game => _fromGame<List<String>>(
              (PlayedGame game) => game.console,
              (List<String> lines) => <_Line>[
                for (final line in lines)
                  if (_keeps(line)) _Line(line),
              ],
            ),
            ConsoleSource.events => _fromGame<List<PostedEvent>>(
              (PlayedGame game) => game.events,
              (List<PostedEvent> events) => <_Line>[
                for (final event in events)
                  if (_keeps('${event.kind} ${jsonEncode(event.data)}'))
                    _Line(
                      '${event.kind}  ${jsonEncode(event.data)}',
                      prefix: '#${event.sequence}',
                    ),
              ],
            ),
          },
        ),
      ],
    );
  }

  /// What the game has kept under [watched], as lines, or why there is none.
  Widget _fromGame<T>(
    Watched<T> Function(PlayedGame game) watched,
    List<_Line> Function(T value) lines,
  ) {
    final game = widget.game;
    if (game == null) {
      return const _Lines(<_Line>[
        _Line('No game is being played — Play the project, or attach to one'),
      ]);
    }
    final source = watched(game);
    return StreamBuilder<T>(
      stream: source.changes,
      initialData: source.value,
      builder: (BuildContext context, _) => _Lines(lines(source.value)),
    );
  }
}

final class _Line {
  const _Line(this.text, {this.prefix, this.error = false});

  final String text;
  final String? prefix;
  final bool error;
}

/// Lines, newest at the bottom and the view kept there as they arrive, the
/// way a terminal does — the same reversed list the Play screen uses.
final class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<_Line> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      key: const ValueKey<String>('console.lines'),
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: lines.length,
      itemBuilder: (BuildContext context, int index) {
        final line = lines[lines.length - 1 - index];
        return SelectableText.rich(
          TextSpan(
            children: <InlineSpan>[
              if (line.prefix case final String prefix)
                TextSpan(
                  text: '$prefix  ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              TextSpan(
                text: line.text,
                style: TextStyle(
                  color: line.error
                      ? const Color(0xFFFF8A80)
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        );
      },
    );
  }
}
