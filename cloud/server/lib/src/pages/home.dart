/// The page a visitor who has never been here lands on.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/user.dart';
import 'layout.dart';

/// What the service is, in the fewest words that are still true.
class HomePage extends StatelessComponent {
  const HomePage({this.signedIn, super.key});

  final User? signedIn;

  @override
  Component build(BuildContext context) {
    return Page(
      title: 'Models',
      description:
          'Keep your 3D models in one place, open them in the browser, and '
          'publish the ones you want other people to use.',
      signedIn: signedIn,
      children: [
        section([
          h1([
            Component.text('Your models, kept somewhere they can be opened'),
          ]),
          p([
            Component.text(
              'Upload a glTF, an OBJ or a flutter3d project, and it is here on '
              'every machine you sign in from. Open it in the browser to look '
              'at it — the same renderer the engine ships with draws it, on '
              'WebGPU where the browser has it.',
            ),
          ], classes: 'lead'),
          if (signedIn == null)
            div([
              a(
                [Component.text('Create an account')],
                href: '/register',
                classes: 'button',
              ),
              a(
                [Component.text('Sign in')],
                href: '/login',
                classes: 'button quiet',
              ),
            ], classes: 'row')
          else
            div([
              a(
                [Component.text('Go to my models')],
                href: '/me',
                classes: 'button',
              ),
            ], classes: 'row'),
        ], classes: 'hero'),
        section([
          _Point(
            title: 'Private until you say otherwise',
            body:
                'An upload is yours alone. Publishing is a separate step, '
                'and it asks which licence the model goes out under.',
          ),
          _Point(
            title: 'Checked before it is stored',
            body:
                'The server reads every upload with the same decoders the '
                'editor uses. A file that does not parse never reaches the '
                'disk, and the triangle count comes from the file rather than '
                'from whoever sent it.',
          ),
          _Point(
            title: 'Attribution travels with the file',
            body:
                'A published model carries its author and licence inside the '
                'exported file, not only on the page it was downloaded from.',
          ),
        ], classes: 'points'),
      ],
    );
  }
}

class _Point extends StatelessComponent {
  const _Point({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Component build(BuildContext context) {
    return article([
      h2([Component.text(title)]),
      p([Component.text(body)]),
    ]);
  }
}
