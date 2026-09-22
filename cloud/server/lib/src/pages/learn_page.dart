/// The modeler tutorial: an index of cases, and each case's own page.
///
/// Public content, the same for every visitor — see `learn_routes.dart` for
/// why neither page carries a signed-in user.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../content/learn_content.dart';
import 'layout.dart';

/// `/learn/modeler/` — every case, in file order, as the same card grid
/// `/me` lists models with.
class LearnIndexPage extends StatelessComponent {
  const LearnIndexPage({required this.cases, super.key});

  final List<LearnCase> cases;

  @override
  Component build(BuildContext context) => Page(
    title: 'Learn the modeler',
    description:
        'Step-by-step cases that build a model, rig it and bring it into a '
        'scene, each one a real job rather than a feature tour.',
    children: [
      article([
        h1([Component.text('Learn the modeler')]),
        if (cases.isEmpty)
          p([
            Component.text(
              'Nothing is published here yet — check back once the '
              'first case lands.',
            ),
          ], classes: 'empty')
        else
          ul([
            for (final one in cases) li([_Card(one)]),
          ], classes: 'cards'),
      ], classes: 'prose'),
    ],
  );
}

class _Card extends StatelessComponent {
  const _Card(this.learnCase);

  final LearnCase learnCase;

  @override
  Component build(BuildContext context) => a(
    [
      div([Component.text('LEARN')], classes: 'thumb'),
      div([
        h2([Component.text(learnCase.title)]),
        if (learnCase.summary.isNotEmpty)
          p([Component.text(learnCase.summary)], classes: 'meta'),
      ], classes: 'body'),
    ],
    href: '/learn/modeler/${learnCase.slug}',
    classes: 'card',
  );
}

/// `/learn/modeler/<slug>` — one case's Markdown, rendered.
class LearnPage extends StatelessComponent {
  const LearnPage({required this.learnCase, super.key});

  final LearnCase learnCase;

  @override
  Component build(BuildContext context) => Page(
    title: learnCase.title,
    description: learnCase.summary.isEmpty ? null : learnCase.summary,
    children: [
      article([RawText(learnCase.bodyHtml)], classes: 'prose'),
      p([
        a([Component.text('Back to all cases')], href: '/learn/modeler/'),
      ]),
    ],
  );
}
