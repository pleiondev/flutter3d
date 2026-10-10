/// Everything [translate.dart] has, and the half that needs a machine: the
/// engine's sources read off disk, glslang and naga run as processes, and a
/// bundle's varyings numbered against the engine's.
///
/// For build scripts and build hooks only. An application never imports this:
/// it carries no shader compiler, and `dart:io` is no help in a browser.
///
/// [translate.dart]: translate.dart
library;

export 'src/bundle_varyings.dart';
export 'src/source_package.dart';
export 'src/wgsl_compiler.dart';
export 'translate.dart';
