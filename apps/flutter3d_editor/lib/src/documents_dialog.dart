/// The documents a level keeps by name — behaviour trees and cutscenes —
/// listed, written as text, and refused with every problem before anything
/// is changed.
///
/// **Text, not a node graph.** A tree is a small JSON document that the
/// level keeps as it is written, the same one an agent sends over
/// `setBehavior`; a box-and-wire editor would be a second way to write it
/// with its own ways to be wrong, and this is the editor where a person and
/// an agent should be able to read each other's work.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Sequence;

/// Shows the trees of [editing]'s level, and answers whether any changed.
Future<bool> showBehaviours(BuildContext context, Editing editing) => _show(
  context,
  DocumentsDialog(
    title: 'Behaviours',
    keyPrefix: 'behaviour',
    documents: () => editing.level.behaviors,
    write: editing.setBehavior,
    remove: editing.removeBehavior,
    fresh: '{\n  "kind": "wait",\n  "seconds": 1\n}',
  ),
);

/// Shows the level's cutscenes — its `cutscene` entities' sequences — and
/// answers whether any changed. A new one stands where the level's origin
/// is until it is moved like any entity.
///
/// [preview] is handed the scene a Preview asks for, read at the editing's
/// step rate and with a camera; what stops it is said in the dialog.
Future<bool> showCutscenes(
  BuildContext context,
  Editing editing, {
  void Function(Sequence scene)? preview,
}) => _show(
  context,
  DocumentsDialog(
    title: 'Cutscenes',
    keyPrefix: 'cutscene',
    documents: () => editing.cutscenes,
    write: editing.setCutscene,
    remove: editing.removeCutscene,
    preview: preview == null
        ? null
        : (Map<String, Object?> document) {
            final read = Sequence.read(
              document,
              stepsPerSecond: editing.cutsceneStepsPerSecond,
            );
            final scene = read.sequence;
            if (scene == null) return read.problems;
            if (!scene.hasCamera) {
              return <String>[
                'it leaves the camera to the game: nothing to show',
              ];
            }
            preview(scene);
            return const <String>[];
          },
    fresh:
        '{\n  "seconds": 3,\n  "subtitles": [\n    {"from": 0, "to": 3, '
        '"text": "…"}\n  ]\n}',
  ),
);

Future<bool> _show(BuildContext context, DocumentsDialog dialog) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => dialog,
    ) ??
    false;

/// Documents a level keeps by name — its behaviour trees, its cutscenes —
/// listed, written as text, and refused with every problem before anything
/// is changed. Every write goes through `Editing`, so each is one step of
/// undo, named after what it wrote.
final class DocumentsDialog extends StatefulWidget {
  const DocumentsDialog({
    super.key,
    required this.title,
    required this.keyPrefix,
    required this.documents,
    required this.write,
    required this.remove,
    required this.fresh,
    this.preview,
  });

  final String title;

  /// What the dialog's widgets are keyed by, `<prefix>:<what>`.
  final String keyPrefix;

  /// The documents as they are now, by name.
  final Map<String, Map<String, Object?>> Function() documents;

  /// Writes one, and answers what was wrong with it — nothing when written.
  final List<String> Function(String name, Map<String, Object?> document) write;

  /// Takes one out, and answers whether there was one.
  final bool Function(String name) remove;

  /// What a new one starts as: the smallest that reads.
  final String fresh;

  /// Shows a document as it is written, saved or not, and answers what
  /// stops it being shown — nothing, and the dialog closes for it. Left out,
  /// there is no Preview button.
  final List<String> Function(Map<String, Object?> document)? preview;

  @override
  State<DocumentsDialog> createState() => _DocumentsDialogState();
}

final class _DocumentsDialogState extends State<DocumentsDialog> {
  final TextEditingController _document = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// The tree being edited, or null when none is.
  String? _open;

  /// What the last save was refused for.
  List<String> _problems = const <String>[];

  /// Whether anything was written, for whoever opened the dialog.
  bool _changed = false;

  Map<String, Map<String, Object?>> get _trees => widget.documents();

  ValueKey<String> _key(String what) =>
      ValueKey<String>('${widget.keyPrefix}:$what');

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
        ? widget.fresh
        : const JsonEncoder.withIndent('  ').convert(tree);
  });

  /// The document as written, or null with what is wrong said.
  Map<String, Object?>? _read() {
    final Object? read;
    try {
      read = jsonDecode(_document.text);
    } on FormatException catch (e) {
      setState(() => _problems = <String>['not JSON: ${e.message}']);
      return null;
    }
    if (read is! Map<String, Object?>) {
      setState(() => _problems = <String>['it has to be a JSON object']);
      return null;
    }
    return read;
  }

  void _preview() {
    final preview = widget.preview;
    final read = _read();
    if (preview == null || read == null) return;
    final problems = preview(read);
    if (problems.isEmpty) {
      Navigator.of(context).pop(_changed);
    } else {
      setState(() => _problems = problems);
    }
  }

  void _save() {
    final name = _open;
    if (name == null) return;
    final read = _read();
    if (read == null) return;
    final problems = widget.write(name, read);
    setState(() {
      _problems = problems;
      if (problems.isEmpty) _changed = true;
    });
  }

  void _remove() {
    final name = _open;
    if (name == null) return;
    if (widget.remove(name)) _changed = true;
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
      title: Text(widget.title),
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
                            key: _key(name),
                            dense: true,
                            title: Text(name),
                            selected: name == open,
                            onTap: () => _show(name),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    key: _key('new-name'),
                    controller: _name,
                    decoration: const InputDecoration(hintText: 'new name'),
                    onSubmitted: (_) => _startNew(),
                  ),
                  TextButton(
                    key: _key('new'),
                    onPressed: _startNew,
                    child: const Text('New'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: open == null
                  ? const Center(child: Text('Pick one, or name a new one'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(open, style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TextField(
                            key: _key('document'),
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
                                key: _key('remove'),
                                onPressed: _remove,
                                child: const Text('Remove'),
                              ),
                            if (widget.preview != null)
                              TextButton(
                                key: _key('preview'),
                                onPressed: _preview,
                                child: const Text('Preview'),
                              ),
                            TextButton(
                              key: _key('save'),
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
