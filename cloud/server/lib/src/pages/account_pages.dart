/// Registering, signing in, and getting back in.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/user.dart';
import 'forms.dart';
import 'layout.dart';
import 'said.dart';

class RegisterPage extends StatelessComponent {
  const RegisterPage({
    required this.csrf,
    this.problems = const {},
    this.email = '',
    this.displayName = '',
    super.key,
  });

  final String csrf;
  final Map<String, String> problems;
  final String email;
  final String displayName;

  @override
  Component build(BuildContext context) => Page(
    title: 'Create account',
    description:
        'Create an account to keep your 3D models and open them in the browser.',
    scripts: const ['password.js'],
    children: [
      div([
        h1([Component.text('Create an account')]),
        PostForm(
          action: '/register',
          csrf: csrf,
          children: [
            Field(
              label: 'Email',
              name: 'email',
              type: InputType.email,
              value: email,
              error: problems['email'],
              autocomplete: 'email',
            ),
            Field(
              label: 'Name',
              name: 'displayName',
              value: displayName,
              error: problems['displayName'],
              hint:
                  'Shown beside anything you publish. Leave it empty to use '
                  'the first part of your address; it can be changed later.',
              autocomplete: 'name',
              required: false,
              maxLength: 60,
            ),
            PasswordFields(
              name: 'password',
              confirmName: 'passwordConfirm',
              error: problems['password'],
              confirmError: problems['passwordConfirm'],
            ),
            submit('Create account'),
          ],
        ),
        p([
          Component.text('Already have one? '),
          a([Component.text('Sign in')], href: '/login'),
          Component.text(
            '. The address is kept to send the two letters an '
            'account needs — see ',
          ),
          a([Component.text('privacy')], href: '/privacy'),
          Component.text('.'),
        ], classes: 'below'),
      ], classes: 'auth'),
    ],
  );
}

class SignInPage extends StatelessComponent {
  const SignInPage({
    required this.csrf,
    this.next = '/me',
    this.email = '',
    this.error,
    this.said,
    super.key,
  });

  final String csrf;
  final String next;
  final String email;
  final String? error;
  final String? said;

  @override
  Component build(BuildContext context) => Page(
    title: 'Sign in',
    children: [
      div([
        h1([Component.text('Sign in')]),
        ?saidNotice(said),
        if (error case final error?) Notice(error, kind: 'error'),
        PostForm(
          action: '/login',
          csrf: csrf,
          children: [
            input(type: InputType.hidden, name: 'next', value: next),
            Field(
              label: 'Email',
              name: 'email',
              type: InputType.email,
              value: email,
              autocomplete: 'email',
            ),
            Field(
              label: 'Password',
              name: 'password',
              type: InputType.password,
              autocomplete: 'current-password',
            ),
            submit('Sign in'),
          ],
        ),
        p([
          a([Component.text('Forgot the password?')], href: '/forgot'),
          Component.text(' · No account yet? '),
          a([Component.text('Create one')], href: '/register'),
          Component.text('.'),
        ], classes: 'below'),
      ], classes: 'auth'),
    ],
  );
}

class ForgotPage extends StatelessComponent {
  const ForgotPage({
    required this.csrf,
    this.email = '',
    this.error,
    this.sentTo,
    super.key,
  });

  final String csrf;
  final String email;
  final String? error;

  /// The address a letter was asked for. When set, the page says what happens
  /// next instead of showing the form again.
  final String? sentTo;

  @override
  Component build(BuildContext context) => Page(
    title: 'Reset password',
    children: [
      div([
        h1([Component.text('Reset the password')]),
        if (sentTo case final address?) ...[
          // The same words whether or not the address has an account: this
          // page must not become a way to find out who is registered.
          Notice(
            'If an account uses $address, a letter with a reset link is on its '
            'way. The link works once and for an hour.',
            kind: 'ok',
          ),
          p([
            Component.text(
              'Nothing after a few minutes? Check the spam folder, or ',
            ),
            a([Component.text('try again')], href: '/forgot'),
            Component.text('.'),
          ], classes: 'below'),
        ] else ...[
          p([
            Component.text(
              'Enter the address the account uses, and a link to '
              'choose a new password will be sent to it.',
            ),
          ], classes: 'muted'),
          if (error case final error?) Notice(error, kind: 'error'),
          PostForm(
            action: '/forgot',
            csrf: csrf,
            children: [
              Field(
                label: 'Email',
                name: 'email',
                type: InputType.email,
                value: email,
                autocomplete: 'email',
              ),
              submit('Send the link'),
            ],
          ),
          p([
            a([Component.text('Back to sign in')], href: '/login'),
          ], classes: 'below'),
        ],
      ], classes: 'auth'),
    ],
  );
}

class ResetPage extends StatelessComponent {
  const ResetPage({
    required this.csrf,
    required this.token,
    this.error,
    super.key,
  });

  final String csrf;
  final String token;
  final String? error;

  @override
  Component build(BuildContext context) => Page(
    title: 'Choose a new password',
    scripts: const ['password.js'],
    children: [
      div([
        h1([Component.text('Choose a new password')]),
        if (token.isEmpty) ...[
          p([
            Component.text('This page needs the link from the reset letter. '),
            a([Component.text('Ask for a letter')], href: '/forgot'),
            Component.text('.'),
          ]),
        ] else ...[
          if (error case final error?) Notice(error, kind: 'error'),
          PostForm(
            action: '/reset',
            csrf: csrf,
            children: [
              input(type: InputType.hidden, name: 'token', value: token),
              const PasswordFields(
                name: 'password',
                confirmName: 'passwordConfirm',
                label: 'New password',
                confirmLabel: 'New password again',
              ),
              p([
                Component.text('Setting it signs the account out everywhere.'),
              ], classes: 'muted'),
              submit('Set the password'),
            ],
          ),
        ],
      ], classes: 'auth'),
    ],
  );
}

class VerifiedPage extends StatelessComponent {
  const VerifiedPage({
    required this.signedIn,
    required this.confirmed,
    super.key,
  });

  final User? signedIn;
  final bool confirmed;

  @override
  Component build(BuildContext context) => Page(
    title: confirmed ? 'Address confirmed' : 'Link expired',
    signedIn: signedIn,
    children: [
      div([
        if (confirmed) ...[
          h1([Component.text('Address confirmed')]),
          p([
            Component.text(
              'Uploading is open. Everything you upload stays private '
              'until you choose otherwise.',
            ),
          ]),
          div([
            a(
              [
                Component.text(
                  signedIn == null ? 'Sign in' : 'Go to my models',
                ),
              ],
              href: signedIn == null ? '/login' : '/me',
              classes: 'button',
            ),
          ], classes: 'row'),
        ] else ...[
          h1([Component.text('This link no longer works')]),
          p([
            Component.text(
              'Confirmation links work once and for 24 hours, and '
              'asking for a new letter retires the old one. Sign in and send '
              'another from your models page.',
            ),
          ]),
          div([
            a(
              [
                Component.text(
                  signedIn == null ? 'Sign in' : 'Go to my models',
                ),
              ],
              href: signedIn == null ? '/login' : '/me',
              classes: 'button',
            ),
          ], classes: 'row'),
        ],
      ], classes: 'auth'),
    ],
  );
}
