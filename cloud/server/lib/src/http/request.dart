/// Reading what a request carries: who sent it, from where, and what it says.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../domain/user.dart';
import '../services.dart';
import 'cookies.dart';

/// The address the request really came from.
///
/// **The header is trusted because nothing else can reach this port.** The
/// service listens on loopback, nginx is the only thing in front of it, and
/// nginx sets `X-Real-IP` from Cloudflare's `CF-Connecting-IP`. On a port
/// anybody could reach, this would be a header anybody could forge.
String clientIp(Request request) {
  final forwarded =
      request.headers['x-real-ip'] ?? request.headers['cf-connecting-ip'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final info =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return info?.remoteAddress.address ?? '0.0.0.0';
}

/// The signed-in account, or null.
Future<User?> userOf(Request request) async {
  final services = Services.instance;
  final token = cookiesOf(request)[services.cookies.sessionName];
  if (token == null || token.isEmpty) return null;
  return services.sessions.whoIs(token);
}

/// The CSRF token a page renders into its forms.
String csrfOf(Request request) =>
    cookiesOf(request)[Services.instance.cookies.csrfName] ?? '';

/// Whether a script's request carries this service's token in `X-CSRF`.
bool scriptIsOurs(Request request) => formIsOurs(request, {
  'csrf': ?request.headers['x-csrf'],
}, Services.instance.cookies);

/// The fields of a urlencoded form, or an empty map for anything else.
Future<Map<String, String>> readForm(
  Request request, {
  int limit = 64 * 1024,
}) async {
  if (request.mimeType != 'application/x-www-form-urlencoded') return const {};
  final body = await readBody(request, limit: limit);
  if (body == null) return const {};
  return Uri.splitQueryString(utf8.decode(body, allowMalformed: true));
}

/// The body, or null when it is larger than [limit].
///
/// Counted as it arrives rather than trusted from `Content-Length`, which a
/// client may omit or understate.
Future<Uint8List?> readBody(Request request, {required int limit}) async {
  final declared = request.contentLength;
  if (declared != null && declared > limit) return null;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > limit) return null;
  }
  return builder.takeBytes();
}

/// Where to go after a POST: 303, so the browser follows with a GET and a
/// reload does not submit the form a second time.
Response seeOther(String location, {Map<String, Object>? headers}) =>
    Response(303, headers: {'location': location, ...?headers});

/// A path to return to after signing in, if it is one of ours.
///
/// Only a path on this host: `//evil.example` is a path to a browser and a
/// host to everybody else, which is what makes an open redirect.
String safeNext(String? next) =>
    next != null &&
        next.startsWith('/') &&
        !next.startsWith('//') &&
        !next.startsWith('/\\')
    ? next
    : '/me';

Response json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
);
