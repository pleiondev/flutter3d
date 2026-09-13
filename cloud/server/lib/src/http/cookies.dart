/// The two cookies the service sets, and the check that a form came from it.
///
/// **`__Host-` in production, plain names on `http://localhost`.** The prefix
/// makes a browser refuse the cookie unless it is `Secure`, has `Path=/` and no
/// `Domain` — so no other subdomain of pleion.dev can set or shadow it. The
/// same prefix on a plain-HTTP development server makes the browser drop the
/// cookie silently, and signing in would appear to do nothing.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../auth/tokens.dart';

class CookiePolicy {
  const CookiePolicy({required this.secure, required this.origin});

  /// Derived from the address the service calls itself.
  factory CookiePolicy.forBaseUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    return CookiePolicy(secure: uri.scheme == 'https', origin: uri.origin);
  }

  final bool secure;

  /// `https://models.pleion.dev` — what a form's `Origin` header must say.
  final String origin;

  String get sessionName => secure ? '__Host-session' : 'session';
  String get csrfName => secure ? '__Host-csrf' : 'csrf';

  String session(String token, Duration maxAge) =>
      _cookie(sessionName, token, maxAge: maxAge);

  String clearSession() => _cookie(sessionName, '', maxAge: Duration.zero);

  String csrf(String token) => _cookie(csrfName, token);

  String _cookie(String name, String value, {Duration? maxAge}) => [
    '$name=$value',
    'Path=/',
    'HttpOnly',
    // Lax, not Strict: a link to /me in a letter or a chat should arrive signed
    // in. Lax still keeps the cookie off a cross-site POST, and the token below
    // covers the browsers that ignore SameSite altogether.
    'SameSite=Lax',
    if (maxAge != null) 'Max-Age=${maxAge.inSeconds}',
    if (secure) 'Secure',
  ].join('; ');
}

/// The cookies a request carries, by name.
Map<String, String> cookiesOf(Request request) => {
  // Trimmed before the `=` is looked for, so that ` =x` is a pair with no name
  // and is dropped, rather than a pair whose name is a space.
  for (final part
      in (request.headers['cookie'] ?? '').split(';').map((p) => p.trim()))
    if (part.indexOf('=') case final eq when eq > 0)
      part.substring(0, eq).trim(): part.substring(eq + 1).trim(),
};

/// Makes sure every request has a CSRF cookie before a page is rendered.
///
/// **The token is written into the request as well as the response.** A page
/// that renders a form reads the token from the request's cookies, and on a
/// visitor's first request there is no cookie yet; putting the fresh one into
/// the request it forwards lets the page find it the same way every time,
/// instead of every form having a first-visit branch.
Middleware csrfCookie(CookiePolicy policy) =>
    (Handler inner) => (Request request) async {
      if (cookiesOf(request).containsKey(policy.csrfName))
        return inner(request);

      final token = newToken();
      final existing = request.headers['cookie'];
      final forwarded = request.change(
        headers: {
          'cookie': [?existing, '${policy.csrfName}=$token'].join('; '),
        },
      );
      final response = await inner(forwarded);
      return response.change(
        headers: {
          'set-cookie': [
            ...?response.headersAll['set-cookie'],
            policy.csrf(token),
          ],
        },
      );
    };

/// Whether a form POST really came from one of this service's pages.
///
/// Two checks, because each covers the other's gap. The token must match the
/// cookie — a page on another site can make the browser send the cookie but
/// cannot read it to put it in the form. And when the browser says where the
/// request came from, it must say here — which catches the cases a leaked
/// token would not.
bool formIsOurs(
  Request request,
  Map<String, String> form,
  CookiePolicy policy,
) {
  final origin = request.headers['origin'];
  if (origin != null && origin != policy.origin) return false;
  if (request.headers['sec-fetch-site'] == 'cross-site') return false;

  final cookie = cookiesOf(request)[policy.csrfName];
  final field = form['csrf'];
  if (cookie == null || field == null || cookie.isEmpty) return false;
  return sameDigest(utf8.encode(cookie), utf8.encode(field));
}
