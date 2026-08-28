/// The name Flutter will ask this plugin's Swift package for.
///
///     flutter test test/swift_package_test.dart
///
/// **A macOS build failed to resolve and nothing in this repository could see
/// it.** Flutter generates a `FlutterGeneratedPluginSwiftPackage` that depends
/// on `.product(name: "pad-input", package: "pad_input")` — the *package* keeps
/// its underscores and the *product* is kebab-cased. This plugin was called
/// `gamepad` when its `Package.swift` was written, where the two spellings are
/// the same word, so the rename produced a product nothing could find and every
/// application that uses a gamepad stopped building for macOS.
///
/// A test rather than a CI build step, because building four applications with
/// Xcode is minutes and this is the one line that was wrong.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Swift product is the plugin name, kebab-cased', () {
    const plugin = 'pad_input';
    final manifest = File('darwin/$plugin/Package.swift').readAsStringSync();

    expect(
      manifest,
      contains('name: "$plugin"'),
      reason: 'the Swift package is not named after the plugin',
    );
    expect(
      manifest,
      contains('.library(name: "${plugin.replaceAll('_', '-')}"'),
      reason:
          'Flutter asks for the product by its kebab-cased name, and '
          'this manifest declares a different one — which fails at '
          '`xcodebuild` with "product not found in package"',
    );
  });
}
