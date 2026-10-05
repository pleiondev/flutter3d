/// N1's panel in the modeller: the project's animation graphs, by name —
/// each with how many states and transitions it has, a tap to open it and a
/// button to remove it — and below them a name and the graph as JSON, set
/// by `SetAnimationGraph`.
///
/// **JSON, not boxes and arrows.** The graph is the shape
/// `AnimationGraphJson` reads, the one an agent sets through MCP and a game
/// reads from the export; this panel edits that text, so what a person
/// writes here and what an agent writes are the same thing. A refusal —
/// the codec's path or the machine's problems against the clips — is shown
/// under the text, where the mistake is.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import '../../l10n/app_localizations.dart';

/// The project's graphs, and an editor for one.
final class AnimationGraphsList extends StatefulWidget {
  const AnimationGraphsList({
    super.key,
    required this.graphs,
    required this.onSet,
    required this.onRemove,
  });

  /// `ModelProject.animationGraphs`.
  final Map<String, Map<String, Object?>> graphs;

  /// Sets graph `name` to `graph`; the refusal, or null when it landed.
  final String? Function(String name, Map<String, Object?> graph) onSet;

  final ValueChanged<String> onRemove;

  @override
  State<AnimationGraphsList> createState() => _AnimationGraphsListState();
}

final class _AnimationGraphsListState extends State<AnimationGraphsList> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _json = TextEditingController();
  String? _refusal;

  @override
  void dispose() {
    _name.dispose();
    _json.dispose();
    super.dispose();
  }

  void _open(String name) => setState(() {
    _name.text = name;
    _json.text = const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.graphs[name]);
    _refusal = null;
  });

  void _set(AppLocalizations l) {
    final Object? decoded;
    try {
      decoded = jsonDecode(_json.text);
    } on FormatException catch (error) {
      setState(() => _refusal = l.animGraphNotJson(error.message));
      return;
    }
    setState(
      () => _refusal = switch (decoded) {
        final Map<String, Object?> graph => widget.onSet(
          _name.text.trim(),
          graph,
        ),
        _ => l.animGraphNotJson('{…}'),
      },
    );
  }

  static int _count(Object? list) => list is List ? list.length : 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(l.animGraphs),
        if (widget.graphs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l.animGraphsNone, style: theme.textTheme.bodySmall),
          ),
        for (final MapEntry(key: name, value: graph) in widget.graphs.entries)
          ListTile(
            key: ValueKey<String>('animation graph $name'),
            dense: true,
            title: Text(name),
            subtitle: Text(
              l.animGraphSummary(
                _count(graph['states']),
                _count(graph['transitions']),
              ),
            ),
            selected: _name.text == name,
            onTap: () => _open(name),
            trailing: IconButton(
              tooltip: l.animGraphRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => widget.onRemove(name),
            ),
          ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('animation graph name'),
          controller: _name,
          decoration: InputDecoration(labelText: l.animGraphName),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('animation graph json'),
          controller: _json,
          minLines: 4,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: l.animGraphJson,
            errorText: _refusal,
            errorMaxLines: 6,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey<String>('animation graph set'),
            onPressed: () => _set(l),
            child: Text(l.animGraphSet),
          ),
        ),
      ],
    );
  }
}
