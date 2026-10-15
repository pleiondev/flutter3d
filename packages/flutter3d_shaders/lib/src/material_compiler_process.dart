/// A backend's material compiler as a process of its own: how the build
/// asks the compiler of a backend from outside the engine, which the build
/// cannot import (D26).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderStageKind;

import 'material_compiler.dart';

/// [request] as the text a compiler's process reads: JSON, with the
/// stages, their GLSL and the engine's headers, and the [options] that are
/// JSON already (a compiler from outside reads none of the engine's own).
String encodeMaterialCompileRequest(MaterialCompileRequest request) =>
    jsonEncode(<String, Object?>{
      'name': request.name,
      'from': request.from,
      'source': request.source,
      'atRunTime': request.atRunTime,
      'stages': <Object?>[
        for (final stage in request.stages)
          <String, Object?>{
            'name': stage.name,
            'kind': stage.kind.name,
            'glsl': stage.glsl,
          },
      ],
      'engineSources': request.engineSources,
      'options': <String, Object?>{
        for (final MapEntry(:key, :value) in request.options.entries)
          if (value == null || value is String || value is num || value is bool)
            key: value,
      },
    });

/// The request [text] holds, as [encodeMaterialCompileRequest] wrote it.
/// Throws a [FormatException] for text that is not one. A key a later
/// build adds is left alone.
MaterialCompileRequest decodeMaterialCompileRequest(String text) {
  switch (jsonDecode(text)) {
    case {
          'name': final String name,
          'from': final String from,
          'source': final String source,
          'stages': final List<Object?> stages,
        } &&
        final Map<String, Object?> json:
      return MaterialCompileRequest(
        name: name,
        from: from,
        source: source,
        atRunTime: json['atRunTime'] == true,
        stages: <MaterialStageSource>[
          for (final stage in stages)
            switch (stage) {
              {
                'name': final String name,
                'kind': final String kind,
                'glsl': final String glsl,
              } =>
                MaterialStageSource(
                  name: name,
                  kind:
                      ShaderStageKind.byName(kind) ??
                      (throw FormatException('no stage kind "$kind"')),
                  glsl: glsl,
                ),
              _ => throw const FormatException('a stage is not one'),
            },
        ],
        engineSources: switch (json['engineSources']) {
          final Map<String, Object?> sources => <String, String>{
            for (final MapEntry(:key, :value) in sources.entries)
              if (value is String) key: value,
          },
          _ => const <String, String>{},
        },
        options: switch (json['options']) {
          final Map<String, Object?> options => options,
          _ => const <String, Object?>{},
        },
      );
    default:
      throw const FormatException('not a material compile request');
  }
}

/// What a backend package's compiler executable runs: [compiler] asked for
/// the request in the file `arguments[0]`, its section written to the file
/// `arguments[1]`. Answers the exit code: 0 for a section written, 65 for
/// a refusal (its sentence on stderr), 64 for arguments that are not two
/// files.
///
/// **How a backend from outside ships its materials in a project.** Its
/// package names the executable in its pubspec, beside the backend it is:
///
/// ```yaml
/// flutter3d_backend:
///   backend: acme_vk          # MaterialCompiler.backend
///   section: acme_vk          # MaterialCompiler.bundleSection
///   compiler: bin/material_compiler.dart
/// ```
///
/// and the executable is one line, `exit(runMaterialCompiler(const
/// AcmeVkMaterialCompiler(), arguments))`. `flutter3d_build`'s hook finds it
/// among the project's dependencies and asks it for its section of the
/// engine's bundle and of every plugin material, as it asks `impellerc`.
int runMaterialCompiler(MaterialCompiler compiler, List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: <compiler> <request.json> <section>: the request a build wrote, '
      'and where the section goes',
    );
    return 64;
  }
  final MaterialCompileResult result;
  try {
    result = compiler.compile(
      decodeMaterialCompileRequest(File(arguments[0]).readAsStringSync()),
    );
  } on MaterialCompileException catch (refused) {
    stderr.writeln(refused.message);
    return 65;
  } on FormatException catch (error) {
    stderr.writeln('the request did not read: ${error.message}');
    return 64;
  }
  final section = result.section;
  File(
    arguments[1],
  ).writeAsBytesSync(Uint8List.sublistView(section), flush: true);
  for (final note in result.notes) {
    stdout.writeln(note);
  }
  return 0;
}
