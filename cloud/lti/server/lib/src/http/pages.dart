/// The handful of pages this service renders when a launch does not reach
/// the viewer — plain string HTML, `cloud/lessons/lib/src/http/pages.dart`'s
/// own reasoning: nothing here has a form or a per-viewer identity, so a
/// string-returning function is the honest amount of machinery.
library;

import 'dart:convert';

const _htmlEscape = HtmlEscape();

/// `/login` or `/launch` got a request naming a platform this service was
/// never told about — the wrong `iss`, most often a registration copied
/// from a different sandbox.
String unknownPlatformPage(String issuer) => _page(
  title: 'Unknown platform',
  body:
      '<p>This service is configured for one LTI platform, and this is not '
      'it.</p>'
      '<p>The request named <code>${_htmlEscape.convert(issuer)}</code>.</p>',
);

/// `/launch` got a `state` this service never issued, or issued too long
/// ago — `pending_login_store.dart`'s `pendingLoginTtl`.
String loginExpiredPage() => _page(
  title: 'Launch expired or never started',
  body:
      '<p>Too much time passed between signing into the LMS and opening the '
      'lesson, or this launch did not start here.</p>'
      '<p>Open the lesson from the LMS again.</p>',
);

/// The `id_token` itself failed verification — [message] is
/// `LtiLaunchException.message`, shown as-is: this is a sandbox tool for
/// registering and debugging an LTI connection, not a page a student sees
/// in the ordinary case, so the exact reason is more useful here than it
/// would be worth hiding.
String launchFailedPage(String message) => _page(
  title: 'Launch not verified',
  body: '<p>${_htmlEscape.convert(message)}</p>',
);

String _page({required String title, required String body}) =>
    '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — flutter3d LTI</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 640px; margin: 3rem auto; padding: 0 1rem; color: #1a1a1a; }
  code { background: #f0f0f0; padding: 0.15em 0.4em; border-radius: 3px; }
</style>
</head>
<body>
<h1>$title</h1>
$body
</body>
</html>
''';

/// Any address this service has no route for at all.
String notFoundPage() =>
    _page(title: 'Not found', body: '<p>This service has no such address.</p>');
