/// The level's behaviour trees: listed, written as their documents, and
/// refused with every problem before anything is changed.
///
/// **Text, not a node graph.** A tree is a small JSON document that the
/// level keeps as it is written, the same one an agent sends over
/// `setBehaviour`; a box-and-wire editor would be a second way to write it
/// with its own ways to be wrong, and this is the editor where a person and
/// an agent should be able to read each other's work.
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

/// Shows the trees of [editing]'s level, and answers whether any changed.
Future<bool> showBehaviours(BuildContext context, Editing editing) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => BehavioursDialog(editing: editing),
    ) ??
    false;

/// The dialog [showBehaviours] shows. Every write goes through `Editing`, so
/// each is one step of undo, named after the tree it wrote.
final class BehavioursDialog extends StatefulWidget {
  const BehavioursDialog({super.key, required this.editing});

  final Editing editing;

  @override
  State<BehavioursDialog> createState() => _BehavioursDialogState();
}

final class _BehavioursDialogState extends State<BehavioursDialog> {
  /// What a new tree starts as: the smallest tree that reads.
  static const String _fresh = '{\n  "kind": "wait",\n  "seconds": 1\n}';

  final TextEditingController _document = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// The tree being edited, or null when none is.
  String? _open;

  /// What the last save was refused for.
  List<String> _problems = const <String>[];

  /// Whether anything was written, for whoever opened the dialog.
  bool _changed = false;

  Map<String, Map<String, Object?>> get _trees =>
      widget.editing.level.behaviours;

  @override
  void dispose() {
    _document.dispose();
    _name.dispose();
    super.dispose();
  }

  void _show(String name) => setState(() {
    _open = name;
    _problems = const <String>[];
    final tree = _trees[name];
    _document.text = tree == null
        ? _fresh
        : const JsonEncoder.withIndent('  ').convert(tree);
  });

  void _save() {
    final name = _open;
    if (name == null) return;
    final Object? read;
    try {
      read = jsonDecode(_document.text);
    } on FormatException catch (e) {
      setState(() => _problems = <String>['not JSON: ${e.message}']);
      return;
    }
    if (read is! Map<String, Object?>) {
      setState(() => _problems = <String>['a tree is a JSON object']);
      return;
    }
    final problems = widget.editing.setBehaviour(name, read);
    setState(() {
      _problems = problems;
      if (problems.isEmpty) _changed = true;
    });
  }

  void _remove() {
    final name = _open;
    if (name == null) return;
    if (widget.editing.removeBehaviour(name)) _changed = true;
    setState(() {
      _open = null;
      _problems = const <String>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = _trees.keys.toList()..sort();
    final open = _open;
    return AlertDialog(
      title: const Text('Behaviours'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        for (final name in names)
                          ListTile(
                            key: ValueKey<String>('behaviour:$name'),
                            dense: true,
                            title: Text(name),
                            selected: name == open,
                            onTap: () => _show(name),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    key: const ValueKey<String>('behaviour:new-name'),
                    controller: _name,
                    decoration: const InputDecoration(hintText: 'new tree'),
                    onSubmitted: (_) => _startNew(),
                  ),
                  TextButton(
                    key: const ValueKey<String>('behaviour:new'),
                    onPressed: _startNew,
                    child: const Text('New'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: open == null
                  ? const Center(child: Text('Pick a tree, or name a new one'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(open, style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>('behaviour:document'),
                            controller: _document,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        for (final problem in _problems)
                          Text(
                            problem,
                            style: const TextStyle(color: Color(0xFFEF5350)),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            if (_trees.containsKey(open))
                              TextButton(
                                key: const ValueKey<String>('behaviour:remove'),
                                onPressed: _remove,
                                child: const Text('Remove'),
                              ),
                            TextButton(
                              key: const ValueKey<String>('behaviour:save'),
                              onPressed: _save,
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _startNew() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _name.clear();
    _show(name);
  }
}
