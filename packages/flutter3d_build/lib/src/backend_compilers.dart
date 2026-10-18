/// The material compilers of the graphics backends from outside the engine
/// among a project's dependencies, found by their pubspec and run as
/// processes (D26).
///
/// **The build cannot import a backend it has never heard of**, and a
/// build hook is compiled before the project's code is. So a backend
/// package names a Dart file that runs its `MaterialCompiler`
/// (`runMaterialCompiler`, `package:flutter3d_shaders/compile.dart`) under
/// `flutter3d_backend:` in its pubspec; discovery reads it
/// ([PluginDiscovery.backendCompilers]), and the build runs that file
/// against the project's package config, handing it each request as a file
/// and reading the section back from another. The backend and its section
/// are read from the pubspec, so knowing who writes what runs nothing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart'
    show flutterSdkRootFrom;
import 'package:flutter3d_shaders/backend.dart'
    show
        MaterialCompileException,
        MaterialCompileRequest,
        MaterialCompileResult,
        MaterialCompiler,
        MaterialCompilerRegistry;
import 'package:flutter3d_shaders/compile.dart'
    show encodeMaterialCompileRequest;

import 'plugin_discovery.dart';

/// The compilers [plugins] found among the project's dependencies, each a
/// [ProcessMaterialCompiler], or null when there are none.
MaterialCompilerRegistry? discoveredCompilers(PluginDiscovery plugins) =>
    plugins.backendCompilers.isEmpty
    ? null
    : MaterialCompilerRegistry(<MaterialCompiler>[
        for (final package in plugins.backendCompilers)
          ProcessMaterialCompiler(package),
      ]);

/// A backend's compiler from outside the engine, run as the Dart file its
/// package names ([BackendCompilerPackage.compiler]).
final class ProcessMaterialCompiler extends MaterialCompiler {
  /// [package]'s compiler, run with [dart] (the Dart running the build by
  /// default).
  ProcessMaterialCompiler(this.package, {String? dart})
    : _dart = dart ?? _dartRunningThis();

  /// The backend package, as discovery read it.
  final BackendCompilerPackage package;

  final String _dart;

  @override
  String get backend => package.backend;

  @override
  String get bundleSection => package.section;

  /// Asks the process for [request]'s section. Throws a
  /// [MaterialCompileException] with what it said when it refuses, or when
  /// it cannot be run at all, naming the package.
  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    final scratch = Directory.systemTemp.createTempSync('flutter3d_compile_');
    try {
      final asked = File('${scratch.path}/request.json')
        ..writeAsStringSync(encodeMaterialCompileRequest(request));
      final out = File('${scratch.path}/section');
      final ProcessResult result;
      try {
        result = Process.runSync(_dart, <String>[
          '--packages=${package.packageConfig}',
          '${package.root}/${package.compiler}',
          asked.path,
          out.path,
        ]);
      } on ProcessException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          MaterialCompileException(
            '${package.name}\'s compiler could not be run with $_dart: '
            '${error.message}',
          ),
          stackTrace,
        );
      }
      if (result.exitCode != 0 || !out.existsSync()) {
        throw MaterialCompileException(
          '${package.name}\'s compiler refused "${request.name}" (exit '
          '${result.exitCode}): ${'${result.stderr}'.trim()}',
        );
      }
      final bytes = out.readAsBytesSync();
      return MaterialCompileResult(
        section: ByteData.sublistView(Uint8List.fromList(bytes)),
        notes: <String>[
          for (final line in '${result.stdout}'.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  @override
  String toString() => 'ProcessMaterialCompiler(${package.name})';
}

/// The `dart` this process runs on: itself, or the one in the Flutter SDK
/// a `flutter_tester` runs from, or the one on the path.
String _dartRunningThis() {
  final executable = Platform.resolvedExecutable;
  final name = executable.split(Platform.pathSeparator).last;
  if (name == 'dart' || name == 'dart.exe') return executable;
  try {
    final sdk = flutterSdkRootFrom(executable);
    final dart = File(
      '$sdk/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
    );
    if (dart.existsSync()) return dart.path;
  } on Exception {
    // Not inside a Flutter SDK: the path's.
  }
  return 'dart';
}
