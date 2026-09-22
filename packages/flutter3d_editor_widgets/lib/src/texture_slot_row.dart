/// One texture slot in a material panel: what it is called, what is bound
/// to it (if anything), and the choose/clear actions a caller offers for
/// changing that.
///
/// **Two rows, merged.** The modeller's own production row was a name (or
/// `"None"`) beside a `Choose…`/`Clear` pair of buttons, with no thumbnail
/// at all; a second, richer row sat beside it wired nowhere — a 26×26
/// preview, a `w×h · weight` [TextureSlotRow.subtitle] and a format
/// [TextureSlotRow.badge], computed once by a caller and handed straight in
/// as bytes and strings, with the whole row a single tap target rather than
/// two buttons. [TextureSlotRow.thumbnail], [TextureSlotRow.subtitle] and
/// [TextureSlotRow.badge] are that richer row's own three optional fields;
/// [TextureSlotRow.onChoose] and [TextureSlotRow.onClear] are the production
/// row's own two actions, kept as buttons because clearing a slot and
/// choosing a new image are two different things a person may want
/// separately, not one tap that could mean either.
///
/// **The thumbnail well only draws once something is there to show in it.**
/// A caller with no [TextureSlotRow.thumbnail] to hand yet gets exactly the
/// production row's own layout back, unchanged.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'editor_widgets_theme.dart';

/// One texture slot's own row.
final class TextureSlotRow extends StatelessWidget {
  const TextureSlotRow({
    super.key,
    required this.label,
    this.name,
    this.subtitle,
    this.badge,
    this.thumbnail,
    required this.onChoose,
    this.onClear,
  });

  /// What this slot binds — `"Base colour texture"`, `"Normal map"` — shown
  /// above the file itself.
  final String label;

  /// The bound file's own name, or null for an empty slot — the row then
  /// shows `"None"` in place of [name].
  final String? name;

  /// `"256×128 · 170 KB"`, or null when a caller has none to show yet.
  final String? subtitle;

  /// A short format badge — `"BC7"`, `"ASTC 4×4"` — or null for a plain
  /// PNG/JPEG, since a badge that always shows says nothing.
  final String? badge;

  /// The bound file's own encoded bytes, decoded into a
  /// [EditorWidgetsTheme.thumbnailSize] preview — or null, which leaves the
  /// thumbnail well out of the row entirely rather than drawing an empty
  /// one.
  final Uint8List? thumbnail;

  final VoidCallback onChoose;

  /// Null hides the button — a slot nothing is bound to has nothing to
  /// clear.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final EditorWidgetsTheme editorTheme = EditorWidgetsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          Row(
            children: <Widget>[
              if (thumbnail case final Uint8List bytes) ...<Widget>[
                _Thumbnail(bytes: bytes, size: editorTheme.thumbnailSize),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name ?? 'None',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: name == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    if (subtitle case final String it)
                      Text(
                        it,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (badge case final String it) ...<Widget>[
                const SizedBox(width: 6),
                _Badge(text: it),
              ],
              TextButton(onPressed: onChoose, child: const Text('Choose…')),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes, required this.size});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          // A file a person just attached is not guaranteed to be one this
          // engine's own decoders read — a KTX2 in a format Flutter's own
          // codec does not know, say. The row still shows the name, size and
          // badge either way; only the pixels are missing.
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  ColoredBox(color: colors.surfaceContainerHighest),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }
}
