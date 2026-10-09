/// "Download as…": a list of links under a `<details>`, so it opens and
/// closes with no script (the pages allow only scripts from `/assets/`).
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../convert/exporter.dart';

/// The menu for one model. [hrefOf] gives each format's address — on a
/// model page `/files/<id>/as/<format>`, on a conversion result
/// `/convert/<id>/as/<format>?path=…`.
class DownloadAsMenu extends StatelessComponent {
  const DownloadAsMenu({
    required this.formats,
    required this.hrefOf,
    this.originalSuffix,
    super.key,
  });

  /// What to offer, in order; see `ExportFormat.offeredFor`.
  final List<ExportFormat> formats;
  final String Function(ExportFormat format) hrefOf;

  /// The stored file's suffix, for the "Original file" line.
  final String? originalSuffix;

  @override
  Component build(BuildContext context) => details([
    summary([Component.text('Download as…')]),
    ul([
      for (final format in formats)
        li([
          a([
            Component.text(
              format == ExportFormat.original && originalSuffix != null
                  ? 'Original file ($originalSuffix)'
                  : format.label,
            ),
          ], href: hrefOf(format)),
        ]),
      li([
        a([
          Component.text('For Blender (.glb)'),
        ], href: hrefOf(ExportFormat.glb)),
        p([
          Component.text(
            'In Blender: File → Import → glTF 2.0. The .usdz opens too, '
            'through File → Import → Universal Scene Description (USD).',
          ),
        ], classes: 'hint'),
      ]),
    ]),
    p([
      Component.text(
        'Written from the stored file on the first download, by the '
        "engine's own writers, and kept for the next one.",
      ),
    ], classes: 'hint'),
  ], classes: 'download-as');
}
