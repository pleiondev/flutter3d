/// A path to a file, typed by hand — the level editor's own "path on disk"
/// model for a [TextureHint], from before an editor could list a project's
/// own assets for a caller to hand in.
///
/// **A callback rather than a listing done here**, because a widget cannot
/// list a disk it was never told about: the editor knows where the open
/// document came from and this file does not. Answering nothing is allowed
/// and is the default — the row is then a path somebody types, which is
/// still the only way to name a file that has not been made yet.
///
/// **A path that does not fit the hint is said, not refused.** The suffixes
/// are what this engine decodes today and a material may legitimately name a
/// file that is not there yet, or one a build step produces. Colouring the
/// line is enough to catch the `.tga` somebody dragged in from another
/// engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart' show TextureHint;

import 'hint_text_box.dart';

/// What a file field may offer to choose from, filtered to the suffixes the
/// hint accepts.
typedef PathOffers = List<String> Function(List<String> suffixes);

/// The default [PathOffers]: nothing can list the files, so nothing is
/// offered. Named rather than written twice, because every caller with no
/// disk of its own wants it.
List<String> nothingToOffer(List<String> suffixes) => const <String>[];

/// A path to a file: a box to type it in, and — when anything can list
/// them — a button that offers the files [offers] names for [hint].
final class TexturePathField extends StatelessWidget {
  const TexturePathField({
    super.key,
    required this.hint,
    required this.path,
    required this.offers,
    required this.onWrite,
  });

  final TextureHint hint;
  final String path;
  final PathOffers offers;
  final void Function(Object? value) onWrite;

  bool get _fits =>
      path.isEmpty ||
      hint.extensions.any((String it) => path.toLowerCase().endsWith(it));

  @override
  Widget build(BuildContext context) {
    final candidates = offers(hint.extensions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: HintTextBox(
                text: path,
                // Emptying it clears the key, for the reason every other
                // text box here does: a texture slot naming nothing is a
                // slot the reader warns about, and "no texture" is what an
                // empty box means to the person who emptied it.
                onWrite: (String text) => onWrite(text.isEmpty ? null : text),
              ),
            ),
            if (candidates.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Choose a file',
                  color: const Color(0xFF8A93A0),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    final picked = await showDialog<String>(
                      context: context,
                      builder: (BuildContext context) =>
                          FilePickerDialog(paths: candidates),
                    );
                    if (picked != null) onWrite(picked);
                  },
                ),
              ),
            ],
          ],
        ),
        if (!_fits)
          Text(
            'not one of ${hint.extensions.join(' ')}',
            style: const TextStyle(color: Color(0xFFD98F4A), fontSize: 10),
          ),
      ],
    );
  }
}

/// The files a [TexturePathField] was offered, to pick one from.
final class FilePickerDialog extends StatelessWidget {
  const FilePickerDialog({super.key, required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    backgroundColor: const Color(0xFF15181D),
    title: const Text(
      'Choose a file',
      style: TextStyle(color: Color(0xFF8A93A0), fontSize: 13),
    ),
    children: <Widget>[
      for (final path in paths)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(path),
          child: Text(
            path,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
    ],
  );
}
