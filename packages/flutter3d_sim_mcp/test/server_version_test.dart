/// The version each of this package's two servers announces, held to the one
/// the package carries.
///
///     flutter test test/server_version_test.dart
///
/// A client logs what a server says it is, and a bug report quotes the log.
/// Both constants said 0.1.0 while the package went to 0.7.0, so every report
/// named a version that never existed.
library;

import 'dart:io';

import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:test/test.dart';

void main() {
  final declared = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);

  test('the pubspec names a version', () => expect(declared, isNotNull));

  test('the playing server says it', () => expect(simMcpVersion, declared));

  test(
    'and so does the diagnostic one',
    () => expect(renderMcpVersion, declared),
  );
}
