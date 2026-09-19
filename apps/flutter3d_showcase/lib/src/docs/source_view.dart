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

/// Where the guide and the source of [feature] live on the documentation
/// site, which is the address of the app's own host. Null on a build that is
/// not served from one.
String kDocsBase = const String.fromEnvironment(
  'SHOWCASE_DOCS',
  defaultValue: 'https://flutter3d.pleion.dev/showcase',
);

Uri githubFileOf(Feature feature) => Uri.parse(
  '$kRepository/blob/main/apps/flutter3d_showcase/${feature.pageFile}',
);

Uri guideOf(Feature feature) => Uri.parse('$kDocsBase/learn/${feature.id}/');

class SourceView extends StatelessWidget {
  const SourceView({
    super.key,
    required this.feature,
    required this.source,
    this.highlight,
  });

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
