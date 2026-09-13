/// The pages that are mostly words.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/user.dart';
import 'layout.dart';

/// A heading, a paragraph and, sometimes, where to go next.
class MessagePage extends StatelessComponent {
  const MessagePage({
    required this.title,
    required this.body,
    this.signedIn,
    this.action,
    super.key,
  });

  final String title;
  final String body;
  final User? signedIn;

  /// A label and a path.
  final (String, String)? action;

  @override
  Component build(BuildContext context) => Page(
    title: title,
    signedIn: signedIn,
    children: [
      div([
        h1([Component.text(title)]),
        p([Component.text(body)]),
        if (action case (final label, final href))
          div([
            a([Component.text(label)], href: href, classes: 'button'),
          ], classes: 'row'),
      ], classes: 'auth'),
    ],
  );
}

class NotFoundPage extends StatelessComponent {
  const NotFoundPage({this.signedIn, super.key});

  final User? signedIn;

  // One page for "no such model" and "a model you may not see". Two would say
  // which private models exist to anybody who counts ids.
  @override
  Component build(BuildContext context) => MessagePage(
    title: 'Nothing here',
    body:
        'The address may be mistyped, or what was here is private or has been deleted.',
    signedIn: signedIn,
    action: signedIn == null
        ? ('Go to the start', '/')
        : ('Go to my models', '/me'),
  );
}

class PrivacyPage extends StatelessComponent {
  const PrivacyPage({this.signedIn, super.key});

  final User? signedIn;

  @override
  Component build(BuildContext context) => Page(
    title: 'Privacy',
    description: 'What flutter3d models keeps about you, and why.',
    signedIn: signedIn,
    children: [
      article([
        h1([Component.text('What is kept, and why')]),
        p([
          Component.text(
            'This service stores what it needs to give you an '
            'account and keep your models, and nothing it does not.',
          ),
        ], classes: 'lead'),
        h2([Component.text('About you')]),
        ul([
          li([
            Component.text(
              'Your email address — to sign you in and to send the '
              'two kinds of letter an account needs: confirming the address, '
              'and resetting a forgotten password.',
            ),
          ]),
          li([
            Component.text(
              'The name you choose, shown beside anything you publish.',
            ),
          ]),
          li([
            Component.text(
              'Your password, as an Argon2id hash. The password itself '
              'is never stored and cannot be read back, by us or anybody.',
            ),
          ]),
          li([
            Component.text(
              'For each signed-in session: when it started, the browser '
              'it was started from and the network address. A session unused for '
              '30 days is deleted.',
            ),
          ]),
          li([
            Component.text(
              'Counts of recent sign-in and reset attempts, to slow '
              'down guessing. They are deleted after a day.',
            ),
          ]),
        ]),
        h2([Component.text('Your models')]),
        p([
          Component.text(
            'The files you upload, and what you write about them. A '
            'model is visible only to you unless you publish it.',
          ),
        ]),
        h2([Component.text('Who else handles it')]),
        p([
          Component.text(
            'Letters are delivered by Resend, which receives the address '
            'and the letter to send it. The service runs on one server; there are '
            'no analytics, no advertising and no scripts from anywhere else on '
            'these pages.',
          ),
        ]),
        h2([Component.text('Deleting it')]),
        p([
          Component.text('Deleting your account from '),
          a([Component.text('settings')], href: '/settings'),
          Component.text(
            ' removes your account, your sessions and your models, '
            'with their files, at once.',
          ),
        ]),
      ], classes: 'prose'),
    ],
  );
}
