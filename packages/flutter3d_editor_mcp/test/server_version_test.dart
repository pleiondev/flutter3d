/// The version the server announces, held to the one the package carries.
///
///     dart test test/server_version_test.dart
///
/// A client logs what a server says it is, and a bug report quotes the log. The
/// constant said 0.1.0 while the package went to 0.6.0 and then 0.7.0, so every
/// report named a version that never existed.
library;

import 'dart:io';

import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('the server says the version its pubspec carries', () {
    final declared = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);

    expect(declared, isNotNull);
    expect(editorMcpVersion, declared);
  });
}
