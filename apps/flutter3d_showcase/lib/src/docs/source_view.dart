/// The Source tab: the file that runs, as it is.
///
/// The region markers are taken out and nothing else is touched, so what is
/// shown is the page's own code. The line numbers are the ones of the stripped
/// text, and a step's region can be scrolled to and marked.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/docs/code_text.dart';
import 'package:flutter3d_showcase/src/docs/regions.dart';
import 'package:url_launcher/url_launcher.dart';

/// The repository the source is linked into. Overridable at build time for a
/// fork.
const String kRepository = String.fromEnvironment(
  'SHOWCASE_REPO',
  defaultValue: 'https://github.com/pleiondev/flutter3d',
);

/// The showcase's part of the documentation site, where [guideOf] finds a
/// page's guide. The public site unless `SHOWCASE_DOCS` names another at
/// build time.
String kDocsBase = const String.fromEnvironment(
  'SHOWCASE_DOCS',
  defaultValue: 'https://flutter3d.pleion.dev/showcase',
);

/// [feature]'s page file on the repository's `main` branch.
Uri githubFileOf(Feature feature) => Uri.parse(
  '$kRepository/blob/main/apps/flutter3d_showcase/${feature.pageFile}',
);

/// [feature]'s guide on the documentation site, under [kDocsBase].
Uri guideOf(Feature feature) => Uri.parse('$kDocsBase/learn/${feature.id}/');

/// The page's Source tab: the file with its markers stripped, numbered, with
/// buttons to copy it and to open it on GitHub.
class SourceView extends StatelessWidget {
  /// A view of [source], marking the region [highlight] when one is given.
  const SourceView({
    super.key,
    required this.feature,
    required this.source,
    this.highlight,
  });

  /// The page whose file this is: its path heads the view and its GitHub
  /// address is what the button opens.
  final Feature feature;

  /// The page file as written, markers included.
  final String source;

  /// A region to mark, or null.
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final String shown = stripMarkers(source).trimRight();
    final int lines = '\n'.allMatches(shown).length + 1;
    final int? marked = highlight == null
        ? null
        : strippedLineOf(source, highlight!);
    final TextStyle style = codeStyle(context);
    final Brightness brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(feature.pageFile, style: style.copyWith(fontSize: 12)),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () => Clipboard.setData(ClipboardData(text: shown)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View on GitHub'),
                onPressed: () => launchUrl(githubFileOf(feature)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectionArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        <String>[
                          for (var n = 1; n <= lines; n++) '$n',
                        ].join('\n'),
                        textAlign: TextAlign.right,
                        style: style.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                    Text.rich(
                      highlightedSpan(shown, style, brightness),
                      key: ValueKey<int?>(marked),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
