/// What a page says after a redirect, and in whose words.
///
/// **A code in the URL, never a sentence.** `/me?said=deleted` looks up its
/// sentence here; `/me?said=<anything else>` shows nothing. A message taken
/// from the query string itself would let any link put words in the service's
/// mouth, on its own domain, above a form asking for a password.
library;

import 'package:jaspr/jaspr.dart';

import 'forms.dart';

const _sentences = <String, (String, String)>{
  'welcome': (
    'ok',
    'Account created. A letter to confirm your address is on its way — '
        'uploading opens once you follow its link.',
  ),
  'verify-sent': ('ok', 'Another confirmation letter is on its way.'),
  'letters-limited': (
    'error',
    'Several letters have gone out in the last hour. Check the spam folder, '
        'or try again later.',
  ),
  'signed-out': ('info', 'Signed out.'),
  'password-reset': ('ok', 'Password changed. Sign in with the new one.'),
  'password-changed': (
    'ok',
    'Password changed, and every session was signed out. Sign in with the new one.',
  ),
  'described': ('ok', 'Saved.'),
  'deleted': ('ok', 'Model deleted.'),
  'moved': ('ok', 'Model moved.'),
  'project-created': ('ok', 'Project created.'),
  'project-deleted': ('ok', 'Project deleted.'),
  'name-saved': ('ok', 'Name saved.'),
};

/// The notice for [code], or nothing when the code is unknown or absent.
Component? saidNotice(String? code) => switch (_sentences[code]) {
  (final kind, final text) => Notice(text, kind: kind),
  null => null,
};
