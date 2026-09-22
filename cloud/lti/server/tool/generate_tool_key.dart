/// Generates this tool's own signing identity for `lti-04`'s AGS score
/// passback — the half of a launch nothing verifying an `id_token` needs,
/// and exactly what `AgsClient` needs to sign a client-credentials
/// assertion the platform can check (`LtiToolCredentials`'s own doc
/// comment).
///
/// A one-time step, run by a person, not by the service on every start: a
/// key regenerated on every deploy would be a key the platform never
/// registered, and every score submission would fail the same way an
/// expired one does. Run it once, register the printed JWKS entry at the
/// platform's own "tool key" screen, and point `LTI_TOOL_KEY_FILE` at the
/// file this writes.
///
///     dart run tool/generate_tool_key.dart /etc/flutter3d-lti/tool-key.json
///
/// Not PEM: `jwk.dart`'s own doc comment on `rsaPrivateKeyToJwk` says why —
/// this package already reads and writes the public half as a JWK, and a
/// second JWK for the private half needs no new format, no ASN.1 framing
/// this dependency graph does not already carry.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_lti/flutter3d_lti.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'usage: dart run tool/generate_tool_key.dart <output.json> [kid]',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final outputPath = args[0];
  final kid = args.length > 1 ? args[1] : 'flutter3d-lti-1';
  final pair = generateRsaKeyPair();

  final file = File(outputPath);
  file.writeAsStringSync(
    jsonEncode(rsaPrivateKeyToJwk(pair.privateKey, kid: kid)),
  );

  stdout.writeln('Wrote $outputPath (kid=$kid).');
  stdout.writeln(
    'chmod 600 it — it is this tool\'s private key, not a public artifact.',
  );
  stdout.writeln('');
  stdout.writeln(
    'Register this JWKS entry at the platform\'s "add a tool key" screen '
    '(or point it at this service\'s own /.well-known/jwks.json, which '
    'serves exactly this once LTI_TOOL_KEY_FILE names the file above):',
  );
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'keys': [rsaPublicKeyToJwk(pair.publicKey, kid: kid)],
    }),
  );
}
