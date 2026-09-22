/// A parsed legal document, on screen — `rel-21d`.
///
/// **Reading, not editing.** Everything else in this application is a panel
/// over a document somebody is changing; this is prose somebody has to be able
/// to get through. So the column is capped at a readable measure rather than
/// stretched to the dialog, the body text is the theme's `bodyMedium` rather
/// than the dense panel size, and the spacing between blocks is what a page
/// has rather than what a property row has.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_document.dart';

/// How wide a line of prose is allowed to get, whatever the window does.
/// Past roughly this the eye loses the start of the next line — the reason
/// every book ever printed is narrower than a desk.
const double kLegalMeasure = 680;

/// [document], rendered as a scrolling page.
class LegalView extends StatefulWidget {
  const LegalView({super.key, required this.document, this.onOpenLink});

  final LegalDocument document;

  /// What a link does. Null means the ordinary thing — hand it to the
  /// platform's browser — and a test passes its own to check what was tapped
  /// without opening anything.
  final ValueChanged<String>? onOpenLink;

  @override
  State<LegalView> createState() => _LegalViewState();
}

class _LegalViewState extends State<LegalView> {
  /// One recogniser per link target, kept for the life of this widget.
  ///
  /// **`TextSpan` takes a `GestureRecognizer` it does not own**, so somebody
  /// has to dispose them, and a `StatelessWidget` building a fresh one per
  /// link per build would leak one per rebuild. Keyed by the href rather than
  /// by position because two mentions of the same address do the same thing,
  /// and because a scroll that rebuilds must not mint a second recogniser for
  /// a link it has already seen.
  final Map<String, GestureRecognizer> _taps = <String, GestureRecognizer>{};

  LegalDocument get document => widget.document;

  @override
  void dispose() {
    for (final GestureRecognizer each in _taps.values) {
      each.dispose();
    }
    super.dispose();
  }

  GestureRecognizer _tapFor(String href) => _taps.putIfAbsent(
    href,
    () => TapGestureRecognizer()
      ..onTap = () {
        final ValueChanged<String>? onOpen = widget.onOpenLink;
        if (onOpen != null) {
          onOpen(href);
          return;
        }
        unawaited(
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication),
        );
      },
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kLegalMeasure),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 32),
          children: <Widget>[
            Text(document.title, style: theme.textTheme.headlineSmall),
            if (document.version.isNotEmpty || document.effective.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  <String>[
                    if (document.version.isNotEmpty)
                      'Version ${document.version}',
                    if (document.effective.isNotEmpty)
                      'effective ${document.effective}',
                  ].join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Divider(height: 24),
            for (final LegalBlock block in document.blocks)
              _block(context, block),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, LegalBlock block) {
    final ThemeData theme = Theme.of(context);
    switch (block) {
      case LegalHeading(:final level, :final text):
        // The document's own `#` is its title, already shown above — drawing
        // it again would give every document two identical headings.
        if (level == 1) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: level == 2 ? 24 : 16, bottom: 6),
          child: _rich(
            context,
            text,
            base: (level == 2
                ? theme.textTheme.titleMedium
                : theme.textTheme.titleSmall),
          ),
        );
      case LegalParagraph(:final text):
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _rich(context, text, base: theme.textTheme.bodyMedium),
        );
      case LegalList(:final items, :final numbered):
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 26,
                        child: Text(
                          numbered ? '${i + 1}.' : '•',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        child: _rich(
                          context,
                          items[i],
                          base: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case LegalCode(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            // Horizontally scrollable rather than wrapped: the one code block
            // in these documents is the MIT licence, and re-wrapping a licence
            // text is not this application's business.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
      case LegalTable(:final header, :final rows):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: kLegalMeasure - 20),
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: double.infinity,
                columns: <DataColumn>[
                  for (final List<LegalSpan> cell in header)
                    DataColumn(
                      label: _rich(
                        context,
                        cell,
                        base: theme.textTheme.labelLarge,
                      ),
                    ),
                ],
                rows: <DataRow>[
                  for (final List<List<LegalSpan>> row in rows)
                    DataRow(
                      cells: <DataCell>[
                        for (var column = 0; column < header.length; column++)
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: _rich(
                                context,
                                column < row.length
                                    ? row[column]
                                    : const <LegalSpan>[],
                                base: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
    }
  }

  Widget _rich(
    BuildContext context,
    List<LegalSpan> spans, {
    required TextStyle? base,
  }) {
    final ThemeData theme = Theme.of(context);
    return SelectableText.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          for (final LegalSpan span in spans)
            TextSpan(
              text: span.text,
              style: TextStyle(
                fontWeight: span.strong ? FontWeight.w600 : null,
                fontFamily: span.code ? 'monospace' : null,
                color: span.href == null ? null : theme.colorScheme.primary,
                decoration: span.href == null ? null : TextDecoration.underline,
                decorationColor: span.href == null
                    ? null
                    : theme.colorScheme.primary,
              ),
              recognizer: span.href == null ? null : _tapFor(span.href!),
            ),
        ],
      ),
    );
  }
}
