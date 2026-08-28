/// The name Flutter will ask this plugin's Swift package for.
///
///     flutter test test/swift_package_test.dart
///
/// **A macOS build failed to resolve and nothing here could see it.** Flutter
/// generates a `FlutterGeneratedPluginSwiftPackage` depending on
/// `.product(name: "pointer-lock", package: "pointer_lock")` — the *package*
/// keeps its underscores and the *product* is kebab-cased. The plugin next door
/// was called `gamepad` when its manifest was written, where the two spellings
/// are the same word, so renaming it to `pad_input` produced a product nothing
/// could find and every application that reads a controller stopped building
/// for macOS. This plugin had the dash all along; the test is here so that it
/// keeps it.
///
/// A test rather than a CI build step, because building four applications with
/// Xcode is minutes and this is the one line that was wrong.
///
/// **`@TestOn('vm')`, since this package grew a browser half.** It reads a
/// manifest off disk, and `dart:io` is not something a browser has; without the
/// annotation the `--platform chrome` pass drags it in and it fails on a missing
/// library rather than on anything about Swift. Same arrangement as
/// `flutter3d_webgl/test/cross_backend_test.dart`, and for the same reason.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Swift product is the plugin name, kebab-cased', () {
    const plugin = 'pointer_lock';
    final manifest = File('macos/$plugin/Package.swift').readAsStringSync();

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
