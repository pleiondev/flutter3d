/// The words of every letter the service sends.
///
/// **Plain strings, not components.** A mail client is not a browser: it drops
/// stylesheets, rewrites classes and renders tables better than flexbox. What
/// survives is simple markup with the style written on the element, and a
/// template engine would only stand between the sentence and that markup.
library;

import 'dart:convert';

import 'mailer.dart';

// Two modes, because the default one also escapes `/`, which turns every link
// into `https:&#47;&#47;…` — valid, and unreadable in the fallback line that
// exists precisely so a person can copy it.
const _escape = HtmlEscape(HtmlEscapeMode.element);
const _attribute = HtmlEscape(HtmlEscapeMode.attribute);

// The paragraphs long enough to wrap, named, so that each list below holds one
// string per paragraph and a missing comma cannot quietly join two of them.
const _verifyBody =
    'Open the link below to confirm that this address is yours. It works once '
    'and for 24 hours.';
const _resetBody =
    'Somebody asked to reset the password of this account. If it was you, '
    'choose a new one below. The link works once and for one hour, and using it '
    'signs you out everywhere.';
const _changedBody =
    'The password of this account was just changed, and every session was '
    'signed out. If that was you, there is nothing to do.';

/// The letter that confirms an address.
Letter verificationLetter({
  required String to,
  required String name,
  required Uri link,
}) => Letter(
  to: to,
  subject: 'Confirm your address for flutter3d models',
  text:
      'Hello $name,\n\n'
      'Open this link to confirm that this address is yours:\n\n'
      '$link\n\n'
      'It works once and for 24 hours. Until the address is confirmed you can '
      'sign in, but not upload.\n\n'
      'If you did not create an account, ignore this letter and nothing '
      'will happen.\n',
  html: _frame(
    heading: 'Confirm your address',
    paragraphs: ['Hello ${_escape.convert(name)},', _verifyBody],
    action: ('Confirm address', link),
    footnote:
        'If you did not create an account, ignore this letter and '
        'nothing will happen.',
  ),
);

/// The letter that sets a new password.
Letter resetLetter({
  required String to,
  required String name,
  required Uri link,
}) => Letter(
  to: to,
  subject: 'Reset your flutter3d models password',
  text:
      'Hello $name,\n\n'
      'Somebody asked to reset the password of this account. If it was you, '
      'open this link to choose a new one:\n\n'
      '$link\n\n'
      'It works once and for one hour. Choosing a new password signs you out '
      'everywhere.\n\n'
      'If it was not you, ignore this letter: your password has not changed.\n',
  html: _frame(
    heading: 'Reset your password',
    paragraphs: ['Hello ${_escape.convert(name)},', _resetBody],
    action: ('Choose a new password', link),
    footnote:
        'If it was not you, ignore this letter: your password has not '
        'changed.',
  ),
);

/// The notice that a password was changed.
///
/// Sent after every change, including one made through a reset link. It is
/// the only way somebody whose account was taken over finds out while there is
/// still time to do something.
Letter passwordChangedLetter({
  required String to,
  required String name,
  required Uri resetLink,
}) => Letter(
  to: to,
  subject: 'Your flutter3d models password was changed',
  text:
      'Hello $name,\n\n'
      'The password of this account was just changed, and every session was '
      'signed out.\n\n'
      'If that was you, there is nothing to do. If it was not, reset the '
      'password now:\n\n'
      '$resetLink\n',
  html: _frame(
    heading: 'Your password was changed',
    paragraphs: ['Hello ${_escape.convert(name)},', _changedBody],
    action: ('It was not me — reset it', resetLink),
    footnote: null,
  ),
);

String _frame({
  required String heading,
  required List<String> paragraphs,
  required (String, Uri) action,
  required String? footnote,
}) {
  final (label, link) = action;
  final href = _attribute.convert(link.toString());
  final body = paragraphs
      .map(
        (p) =>
            '<p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#10161c">$p</p>',
      )
      .join();
  final note = footnote == null
      ? ''
      : '<p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:#5c6c7a">'
            '${_escape.convert(footnote)}</p>';

  return '''
<!doctype html>
<html lang="en">
<body style="margin:0;padding:32px 16px;background:#f7f8f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid #d8dfe6;border-radius:4px">
<tr><td style="padding:32px">
<p style="margin:0 0 24px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:14px;color:#b8530e">flutter3d models</p>
<h1 style="margin:0 0 20px;font-size:22px;line-height:1.3;color:#10161c">${_escape.convert(heading)}</h1>
$body
<p style="margin:24px 0 0"><a href="$href" style="display:inline-block;padding:12px 20px;background:#b8530e;color:#ffffff;text-decoration:none;border-radius:4px;font-weight:600">${_escape.convert(label)}</a></p>
<p style="margin:20px 0 0;font-size:13px;line-height:1.5;color:#5c6c7a;word-break:break-all">Or paste this address into your browser:<br>$href</p>
$note
</td></tr></table>
</td></tr></table>
</body>
</html>''';
}
