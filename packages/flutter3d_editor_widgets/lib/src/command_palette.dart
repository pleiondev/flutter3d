/// Every command an editor has, found by typing a few letters of its name.
///
/// **The keys, the toolbar and the menus each knew some of what the editor
/// could do, and nothing knew all of it.** A person who has forgotten which
/// key folds the lamp, or never knew there was a light optimizer, has
/// nowhere to ask. A palette is that place: one list of everything, searched
/// by name, with the shortcut beside each so the next time it is a key.
///
/// The matching is [fuzzyScore]: the letters typed must appear in the title
/// in order, and a match that starts words or runs letters together ranks
/// above one scattered through the middle — so `sac` finds "Save a copy" by
/// its initials, ahead of every title that merely has those three letters
/// somewhere in it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One thing the palette can run.
final class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.title,
    required this.run,
    this.shortcut,
    this.enabled = true,
  });

  final String id;

  /// What it is called, and what is searched.
  final String title;

  /// The keys that do the same, as a person would write them, or null.
  final String? shortcut;

  /// Whether it can run now; a command that cannot is listed, dimmed, so
  /// somebody looking for it learns that it exists.
  final bool enabled;
  final VoidCallback run;
}

/// How well [query] matches [text], or null when it does not.
///
/// Every character of [query] must appear in [text], in order, ignoring
/// case. Each one found scores a point; one that follows the previous match
/// directly, or starts a word, scores more; and a shorter [text] wins a tie,
/// since fewer letters left over means the match explains more of it.
int? fuzzyScore(String query, String text) {
  final wanted = query.toLowerCase().replaceAll(' ', '');
  if (wanted.isEmpty) return 0;
  final lower = text.toLowerCase();
  var score = 0;
  var from = 0;
  var previous = -2;
  for (final char in wanted.split('')) {
    final at = lower.indexOf(char, from);
    if (at < 0) return null;
    final startsWord = at == 0 || lower[at - 1] == ' ' || lower[at - 1] == '-';
    score += 1 + (at == previous + 1 ? 4 : 0) + (startsWord ? 6 : 0);
    previous = at;
    from = at + 1;
  }
  return score * 100 - text.length;
}

/// [commands] that match [query], best first; all of them, in their own
/// order, when [query] is empty.
List<PaletteCommand> rankCommands(List<PaletteCommand> commands, String query) {
  if (query.trim().isEmpty) return commands;
  final scored = <(PaletteCommand, int)>[
    for (final command in commands)
      if (fuzzyScore(query, command.title) case final int score)
        (command, score),
  ]..sort(((PaletteCommand, int) a, (PaletteCommand, int) b) => b.$2 - a.$2);
  return <PaletteCommand>[for (final (command, _) in scored) command];
}

/// Opens the palette over [context] and runs whatever is chosen.
///
/// The command runs after the palette has closed, so one that opens a
/// dialog of its own opens it over the editor rather than over the palette.
Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteCommand> commands,
) async {
  final chosen = await showDialog<PaletteCommand>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (BuildContext context) => CommandPalette(commands: commands),
  );
  chosen?.run();
}

/// The palette itself: a box to type in and the commands that match.
///
/// Up and down move through the list, Enter runs the one highlighted, Escape
/// closes it; a click runs the row clicked. It answers the command chosen by
/// popping the route it was pushed in, which [showCommandPalette] does.
final class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});

  final List<PaletteCommand> commands;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _field = FocusNode();

  /// Which row Enter would run. State, because it is where the arrow keys
  /// have moved it to.
  int _at = 0;

  List<PaletteCommand> get _shown => rankCommands(widget.commands, _query.text);

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _choose(PaletteCommand command) {
    if (!command.enabled) return;
    Navigator.of(context).pop(command);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shown = _shown;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when shown.isNotEmpty:
        setState(() => _at = (_at + 1) % shown.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when shown.isNotEmpty:
        setState(() => _at = (_at - 1 + shown.length) % shown.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when shown.isNotEmpty:
        _choose(shown[_at.clamp(0, shown.length - 1)]);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    final at = shown.isEmpty ? -1 : _at.clamp(0, shown.length - 1);
    return Align(
      alignment: const Alignment(0.0, -0.6),
      child: Material(
        color: scheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const ValueKey<String>('palette.query'),
                  controller: _query,
                  focusNode: _field,
                  autofocus: true,
                  style: TextStyle(color: scheme.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Type a command',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  // A new query is a new list, and the highlight goes back to
                  // its best match rather than staying on a row number that
                  // now means something else.
                  onChanged: (String _) => setState(() => _at = 0),
                ),
              ),
              Divider(height: 1, color: scheme.outline),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No command matches',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: shown.length,
                        itemBuilder: (BuildContext context, int index) => _Row(
                          command: shown[index],
                          highlighted: index == at,
                          onTap: () => _choose(shown[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Row extends StatelessWidget {
  const _Row({
    required this.command,
    required this.highlighted,
    required this.onTap,
  });

  final PaletteCommand command;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = command.enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.6);
    return InkWell(
      key: ValueKey<String>('palette.row.${command.id}'),
      onTap: command.enabled ? onTap : null,
      child: Container(
        color: highlighted ? scheme.primary.withValues(alpha: 0.18) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                command.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
            if (command.shortcut case final String keys)
              Text(
                keys,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
