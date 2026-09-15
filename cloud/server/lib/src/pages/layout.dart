/// The frame every page is drawn in.
///
/// One file, because the alternative is a header that drifts: the cabinet's
/// copy learns a link the settings page's copy does not have, and which one is
/// right stops being answerable. The palette is the documentation site's own —
/// a service that looks like the site it belongs to does not have to say so.
library;

import 'package:jaspr/dom.dart';
// The server library, not `jaspr.dart`: the document is only ever built here,
// and the plain import resolves `Document` to the client stub, which has no
// unnamed constructor.
import 'package:jaspr/server.dart';

import '../domain/user.dart';

/// A finished page: the document, the bar across the top, and [children] under
/// it.
///
/// [signedIn] decides what the bar offers, not what the page shows. A page that
/// needs an account has already redirected by the time it is built.
class Page extends StatelessComponent {
  const Page({
    required this.title,
    required this.children,
    this.signedIn,
    this.description,
    this.wide = false,
    this.scripts = const [],
    super.key,
  });

  /// Goes into `<title>`, with the service's name after it.
  final String title;

  /// The meta description, for a link that ends up in a search result or a
  /// message. Absent on pages nobody links to.
  final String? description;

  final User? signedIn;

  /// Whether the content wants the full width — a grid of models does, a
  /// sign-in form does not.
  final bool wide;

  /// Scripts under `/assets/`, by name. Files and never inline: the content
  /// security policy allows nothing else, which is the point of it.
  final List<String> scripts;

  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return Document(
      title: '$title · flutter3d models',
      lang: 'en',
      meta: {'description': ?description, 'color-scheme': 'dark light'},
      head: [
        link(href: '/assets/styles.css', rel: 'stylesheet'),
        link(href: '/assets/favicon.svg', rel: 'icon'),
        for (final name in scripts)
          script(src: '/assets/$name', attributes: const {'defer': ''}),
      ],
      body: div([
        a(
          [Component.text('Skip to content')],
          href: '#content',
          classes: 'skip',
        ),
        _TopBar(signedIn: signedIn),
        main_(
          children,
          id: 'content',
          classes: wide ? 'content wide' : 'content',
        ),
        const _Footer(),
      ], classes: 'shell'),
    );
  }
}

class _TopBar extends StatelessComponent {
  const _TopBar({this.signedIn});

  final User? signedIn;

  @override
  Component build(BuildContext context) {
    return header([
      a(
        [
          Component.text('flutter3d'),
          span([Component.text('models')], classes: 'brand-tail'),
        ],
        href: '/',
        classes: 'brand',
      ),
      nav([
        a([Component.text('Learn')], href: '/learn/modeler/'),
        if (signedIn case final user?) ...[
          a([Component.text('My models')], href: '/me'),
          a([Component.text('My projects')], href: '/projects'),
          a(
            [Component.text(user.displayName)],
            href: '/settings',
            classes: 'who',
          ),
        ] else ...[
          a([Component.text('Sign in')], href: '/login'),
          a(
            [Component.text('Create account')],
            href: '/register',
            classes: 'cta',
          ),
        ],
      ]),
    ], classes: 'topbar');
  }
}

class _Footer extends StatelessComponent {
  const _Footer();

  @override
  Component build(BuildContext context) {
    return footer([
      a([
        Component.text('Documentation'),
      ], href: 'https://flutter3d.pleion.dev/'),
      a([
        Component.text('Source'),
      ], href: 'https://github.com/pleiondev/flutter3d'),
      a([Component.text('Privacy')], href: '/privacy'),
    ], classes: 'foot');
  }
}
