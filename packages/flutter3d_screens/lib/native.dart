/// The parts of this package that need a filesystem.
///
///     import 'package:flutter3d_screens/native.dart';
///
/// A second entry point rather than more exports on the main barrel, for the
/// reason `flutter3d_hardware/testing.dart` is one: `flutter3d_screens.dart` is
/// imported by games that build for the web, and a `dart:io` import anywhere
/// behind it makes the whole package refuse to compile there. What is here
/// needs `File` and says so by being somewhere a web build never looks.
///
/// One thing so far — writing a document without the moment where it is half a
/// document, which the editor needed and had written the unsafe version of.
library;

export 'src/storage/atomic_write.dart';
