/// Every address this service answers.
///
/// Two routes carry the whole of an LTI 1.3 launch (IMS Security Framework
/// §5): `/login` answers the platform's third-party login initiation with a
/// redirect back to the platform's own authorization endpoint; `/launch`
/// receives the `id_token` that redirect eventually produces, verifies it,
/// and — once it checks out — hands the browser to the lesson viewer. A
/// third route, `/app/`, is that viewer's own web build. A fourth,
/// `/launch/<token>/check-result` (`lti-04`), is the wire from a `check`
/// question back to this launch's platform and LRS.
library;

import 'dart:convert';
import 'dart:io' show stderr;

import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../launch_session_store.dart';
import '../lessons_registry.dart';
import '../pending_login_store.dart';
import '../session_token.dart';
import 'pages.dart';
import 'static_files.dart';

/// [validator] is an injection point for a test to give this a
/// `LtiLaunchValidator` built with a fake HTTP client, so a launch route can
/// be exercised without this service reaching out to a real JWKS endpoint.
/// [httpClient] is the same idea for `check-result`'s own outgoing calls
/// (`AgsClient`'s client-credentials grant and score POST, `XapiClient`'s
/// statement PUT) — a fake AGS/LRS endpoint for a test, a real
/// `http.Client()` (each client's own default) in `main.server.dart`, which
/// never passes one.
Handler buildHandler(
  Config config, {
  LtiLaunchValidator? validator,
  http.Client? httpClient,
}) {
  final pendingLogins = PendingLoginStore();
  final launchSessions = LaunchSessionStore();
  final ltiValidator =
      validator ?? LtiLaunchValidator(platform: config.platform);

  // Built once per process, not per request: `AgsClient`'s own doc comment
  // says its access token is meant to be reused across submissions until
  // close to expiring, which a client rebuilt on every `check-result`
  // could never do. Null exactly when `Config` says this half is not
  // configured — the same "an LTI launch with no AGS claim" honest absence
  // the config layer already keeps.
  //
  // **Both `toolCredentials` and `platform.authTokenUrl`, not just the
  // first.** `AgsClient`'s own constructor throws when the platform names
  // no token endpoint — an operator who set `LTI_TOOL_KEY_FILE` without
  // also setting `LTI_PLATFORM_AUTH_TOKEN_URL` should get a server that
  // still serves `/.well-known/jwks.json` and skips AGS, not one that
  // throws on its very first request.
  final agsClient = switch ((
    config.toolCredentials,
    config.platform.authTokenUrl,
  )) {
    (final credentials?, final _?) => AgsClient(
      platform: config.platform,
      credentials: credentials,
      httpClient: httpClient,
    ),
    _ => null,
  };
  final xapiClient = switch (config.lrs) {
    final lrs? => XapiClient(lrs: lrs, httpClient: httpClient),
    null => null,
  };

  final router = Router(notFoundHandler: _notFound)
    ..get('/health', (Request request) => Response.ok('ok'))
    ..all('/login', (Request request) => _login(request, config, pendingLogins))
    ..post(
      '/launch',
      (Request request) =>
          _launch(request, config, pendingLogins, launchSessions, ltiValidator),
    )
    ..post(
      '/launch/<token>/check-result',
      (Request request, String token) => _checkResult(
        request,
        config,
        launchSessions,
        token,
        agsClient: agsClient,
        xapiClient: xapiClient,
      ),
    )
    ..get('/.well-known/jwks.json', (Request request) => _jwks(config));

  if (config.viewerDirectory case final viewer?) {
    router.mount('/app/', staticDirectory(viewer, cacheControl: 'no-cache'));
  }

  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}

/// The third-party login initiation the platform sends before every launch
/// — commonly a GET, sometimes a POST; this service reads whichever
/// carried the parameters rather than picking one, since the spec allows
/// both and Moodle's own external-tool launch uses a plain link.
Future<Response> _login(
  Request request,
  Config config,
  PendingLoginStore pendingLogins,
) async {
  final params = await _requestParams(request);

  final issuer = params['iss'];
  if (issuer != config.platform.issuer) {
    return _html(unknownPlatformPage(issuer ?? '(missing)'), status: 400);
  }

  final initiation = OidcLoginInitiation(
    platform: config.platform,
    toolLaunchUri: Uri.parse('${config.baseUrl}/launch'),
  );
  final redirect = initiation.buildRedirect(
    loginHint: params['login_hint'] ?? '',
    ltiMessageHint: params['lti_message_hint'],
  );
  pendingLogins.add(redirect.state, redirect.nonce);

  return Response.found(redirect.uri);
}

/// The platform's answer to `/login`'s redirect: an `id_token` and the
/// `state` this service handed out, posted as `application/x-www-form-
/// urlencoded` (`response_mode=form_post`).
Future<Response> _launch(
  Request request,
  Config config,
  PendingLoginStore pendingLogins,
  LaunchSessionStore launchSessions,
  LtiLaunchValidator validator,
) async {
  final params = await _requestParams(request);
  final idToken = params['id_token'];
  final state = params['state'];
  if (idToken == null || state == null) {
    return _html(
      launchFailedPage('request carries neither id_token nor state'),
      status: 400,
    );
  }

  final pending = pendingLogins.take(state);
  if (pending == null) {
    return _html(loginExpiredPage(), status: 400);
  }

  final LtiLaunchClaims claims;
  try {
    claims = await validator.verify(
      idToken,
      expectedState: state,
      receivedState: state,
      expectedNonce: pending.nonce,
    );
  } on LtiLaunchException catch (error) {
    return _html(launchFailedPage(error.message), status: 400);
  }

  final token = generateSessionToken();
  launchSessions.add(
    token,
    LaunchSession(
      claims: claims,
      lessonAsset: defaultLessonAsset(),
      issuedAt: DateTime.now(),
    ),
  );

  final viewerUrl = Uri.parse(
    '${config.baseUrl}/app/',
  ).replace(queryParameters: {'level': defaultLessonAsset(), 'launch': token});
  return Response.found(viewerUrl);
}

/// `lti-04`: the lesson viewer's own report of a `check` outcome, wired to
/// both of `doc/edu-00-interactive-format.md` §10's destinations at once —
/// "оба пути разом, без выбора одного вместо другого"
/// (`doc/edu-03-lti-plan.md`'s own acceptance line for this route). Each
/// half is attempted independently: a launch with no AGS claim, or a
/// deployment with no LRS configured, still gets whichever half applies,
/// and a failure in one does not withhold the other.
Future<Response> _checkResult(
  Request request,
  Config config,
  LaunchSessionStore launchSessions,
  String token, {
  required AgsClient? agsClient,
  required XapiClient? xapiClient,
}) async {
  final session = launchSessions.get(token);
  if (session == null) {
    return _json({'error': 'unknown or expired launch'}, status: 404);
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } on FormatException {
    return _json({'error': 'body is not valid JSON'}, status: 400);
  }
  final step = body['step'];
  final correct = body['correct'];
  if (step is! String || step.isEmpty || correct is! bool) {
    return _json({
      'error': 'body needs a non-empty "step" (string) and "correct" (bool)',
    }, status: 400);
  }

  final claims = session.claims;
  final ags = await _submitAgsScore(agsClient, claims, correct: correct);
  final xapi = await _sendXapiStatement(
    xapiClient,
    config,
    claims,
    step: step,
    correct: correct,
  );
  return _json({'ags': ags, 'xapi': xapi});
}

/// This tool's own JWKS — what a platform fetches to verify the client
/// assertion `AgsClient` signs for a client-credentials grant (IMS Security
/// Framework §5.4.1's own mirror of what `LtiLaunchValidator` already does
/// for a *platform's* JWKS). An empty key set, not a 404, when no tool key
/// is configured: this is a real endpoint that answers honestly about
/// having nothing to publish, not a route that only exists once `lti-04`'s
/// AGS half is turned on.
Response _jwks(Config config) {
  final credentials = config.toolCredentials;
  return _json({
    'keys': [
      if (credentials != null)
        rsaPublicKeyToJwk(credentials.publicKey, kid: credentials.kid),
    ],
  });
}

const _agsScoreScope = 'https://purl.imsglobal.org/spec/lti-ags/scope/score';

/// True on a submitted score, false for every reason this launch was never
/// going to have one — no tool key configured ([client] null), no line
/// item, no scope — and also false, rather than thrown, when the platform
/// itself refuses the POST: one student's ungraded question should not
/// crash the request the browser is waiting on.
Future<bool> _submitAgsScore(
  AgsClient? client,
  LtiLaunchClaims claims, {
  required bool correct,
}) async {
  final lineItem = claims.agsLineItemUrl;
  if (client == null ||
      lineItem == null ||
      !claims.agsScopes.contains(_agsScoreScope)) {
    return false;
  }

  try {
    await client.submitScore(
      AgsScore(
        userId: claims.subject,
        scoreGiven: correct ? 1 : 0,
        scoreMaximum: 1,
      ),
      lineItemUrl: lineItem,
    );
    return true;
  } on AgsException catch (error) {
    stderr.writeln('check-result: AGS submission failed: $error');
    return false;
  }
}

/// True on a sent statement, false when no LRS is configured ([client]
/// null) or the LRS itself refuses the PUT — [_submitAgsScore]'s own
/// "report, do not throw" choice, for the same reason.
Future<bool> _sendXapiStatement(
  XapiClient? client,
  Config config,
  LtiLaunchClaims claims, {
  required String step,
  required bool correct,
}) async {
  if (client == null) return false;

  try {
    await client.send(
      XapiStatement(
        actor: XapiActor.fromLtiSubject(
          name: claims.subject,
          platformIssuer: config.platform.issuer,
          subject: claims.subject,
        ),
        verb: XapiVerb.answered,
        object: XapiActivity(id: '${config.baseUrl}/launch#$step', name: step),
        result: XapiResult(success: correct, scoreScaled: correct ? 1.0 : 0.0),
      ),
    );
    return true;
  } on XapiException catch (error) {
    stderr.writeln('check-result: xAPI statement failed: $error');
    return false;
  }
}

Response _json(Map<String, Object?> body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Query parameters for a GET, form-decoded body for a POST — the two
/// shapes an LTI login initiation or launch arrives in.
Future<Map<String, String>> _requestParams(Request request) async {
  if (request.method == 'GET') return request.url.queryParameters;
  final body = await request.readAsString();
  return Uri.splitQueryString(body);
}

Response _notFound(Request request) => _html(notFoundPage(), status: 404);

Response _html(String body, {int status = 200}) => Response(
  status,
  body: body,
  headers: {'content-type': 'text/html; charset=utf-8'},
);
