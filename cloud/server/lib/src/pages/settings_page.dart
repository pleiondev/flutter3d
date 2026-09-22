/// The account itself: its name, its password, signing out and leaving.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/user.dart';
import 'forms.dart';
import 'layout.dart';
import 'said.dart';

class SettingsPage extends StatelessComponent {
  const SettingsPage({
    required this.user,
    required this.csrf,
    this.said,
    this.nameError,
    this.passwordError,
    this.deleteError,
    super.key,
  });

  final User user;
  final String csrf;
  final String? said;
  final String? nameError;
  final String? passwordError;
  final String? deleteError;

  @override
  Component build(BuildContext context) => Page(
    title: 'Settings',
    signedIn: user,
    scripts: const ['password.js'],
    children: [
      h1([Component.text('Settings')]),
      ?saidNotice(said),
      section([
        dl([
          dt([Component.text('Email')]),
          dd([Component.text(user.email)]),
          dt([Component.text('Address')]),
          dd([
            Component.text(
              user.emailVerified ? 'confirmed' : 'not confirmed yet',
            ),
          ]),
        ], classes: 'facts'),
      ], classes: 'settings'),
      section([
        h2([Component.text('Name')]),
        p([Component.text('Shown beside anything you publish.')]),
        PostForm(
          action: '/settings/name',
          csrf: csrf,
          children: [
            Field(
              label: 'Name',
              name: 'displayName',
              value: user.displayName,
              error: nameError,
              autocomplete: 'name',
              maxLength: 60,
            ),
            div([submit('Save name')]),
          ],
        ),
      ], classes: 'settings'),
      section([
        h2([Component.text('Password')]),
        p([
          Component.text(
            'Changing it signs you out everywhere, including here.',
          ),
        ]),
        if (passwordError case final error?) Notice(error, kind: 'error'),
        PostForm(
          action: '/settings/password',
          csrf: csrf,
          children: [
            const Field(
              label: 'Current password',
              name: 'current',
              type: InputType.password,
              autocomplete: 'current-password',
            ),
            const PasswordFields(
              name: 'next',
              confirmName: 'nextConfirm',
              label: 'New password',
              confirmLabel: 'New password again',
            ),
            div([submit('Change password')]),
          ],
        ),
      ], classes: 'settings'),
      section([
        h2([Component.text('Sign out')]),
        PostForm(
          action: '/logout',
          csrf: csrf,
          classes: '',
          children: [submit('Sign out of this browser', classes: 'quiet')],
        ),
      ], classes: 'settings'),
      section([
        details(
          [
            summary([Component.text('Delete my account')]),
            PostForm(
              action: '/settings/delete',
              csrf: csrf,
              children: [
                p([
                  Component.text(
                    'Your account, every model and every file are removed '
                    'at once. This cannot be undone.',
                  ),
                ]),
                Field(
                  label: 'Your password',
                  name: 'password',
                  type: InputType.password,
                  error: deleteError,
                  autocomplete: 'current-password',
                ),
                div([
                  submit('Delete account and all models', classes: 'danger'),
                ]),
              ],
            ),
          ],
          // Open when the password was wrong, so the error is not hidden
          // behind a summary the person has to find and click again.
          open: deleteError != null,
          classes: 'danger',
        ),
      ], classes: 'settings'),
    ],
  );
}
