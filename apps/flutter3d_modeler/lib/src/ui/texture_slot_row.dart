/// `TextureSlotRow`: one texture slot in a material panel — `mat-05`'s own
/// row.
///
/// **Dumb on purpose.** Everything this draws is already computed —
/// `texture_slot.dart`'s [TextureSlotDisplay] — and picking a new image is a
/// `VoidCallback` this widget fires and never itself opens a picker for. A
/// panel wiring five of these together decides what "pick" means on its own
/// platform (`file_selector` behind `project_files_io.dart`'s conditional
/// export, on desktop and web alike); this file does not import
/// `file_selector` at all, so it needs no platform seam of its own and its
/// test needs no fake file picker.
///
///     flutter test test/ui/texture_slot_row_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../texture_slot.dart';
import 'theme.dart';

/// One row: a 26×26 thumbnail, the file's name, its `w×h`/weight/format line,
/// and a button that asks the parent to offer a different image.
class TextureSlotRow extends StatelessWidget {
  const TextureSlotRow({
    super.key,
    required this.label,
    required this.display,
    required this.onPick,
  });

  /// What this slot binds — `"Base colour"`, `"Normal"` — shown above the
  /// file itself, the same way a material's own field names are shown
  /// elsewhere in this panel.
  final String label;

  /// Null when nothing is bound to this slot yet — the row then shows
  /// [label] and an empty thumbnail well, with [onPick] still live.
  final TextureSlotDisplay? display;

  final VoidCallback onPick;

  /// `mat-05`'s own acceptance: a 26×26 preview, not a size this row invents.
  static const double thumbnailSize = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = display;
    return InkWell(
      onTap: onPick,
      child: SizedBox(
        height: ModelerMetrics.row + 4,
        child: Row(
          children: <Widget>[
            _Thumbnail(bytes: current?.thumbnail),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    current?.name ?? label,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    current == null ? 'None' : _subtitle(current),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (current?.formatBadge case final String badge) ...<Widget>[
              const SizedBox(width: 6),
              _Badge(text: badge),
            ],
          ],
        ),
      ),
    );
  }

  /// `"256×128 · 170 КБ"`, or just the weight when the header could not be
  /// read — see [TextureSlotDisplay.dimensionsText].
  String _subtitle(TextureSlotDisplay it) => it.dimensionsText == null
      ? it.weightText
      : '${it.dimensionsText} · ${it.weightText}';
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: TextureSlotRow.thumbnailSize,
        height: TextureSlotRow.thumbnailSize,
        child: bytes == null
            ? ColoredBox(color: colors.surfaceContainerHighest)
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                // A file a person just attached is not guaranteed to be one
                // this engine's own decoders read — a KTX2 in a format
                // Flutter's own codec does not know, say. The row still shows
                // the name, size and badge either way; only the pixels are
                // missing.
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) => ColoredBox(color: colors.surfaceContainerHighest),
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
    final colors = Theme.of(context).colorScheme;
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
