/// No vertex stage reads a built-in index on the OpenGL ES path.
///
///     flutter test test/gles_vertex_index_test.dart
///
/// **Impeller's OpenGL ES backend compiles the bundle as GLSL ES 1.00**, which
/// has neither `gl_VertexID` nor `gl_InstanceID`. `impellerc` does not object:
/// it writes the built-in into a `#version 100` source and the driver refuses
/// it when the stage is compiled at run time, so a Linux machine (and an
/// Android phone without Vulkan) drew nothing at all. The morph columns and
/// the instance rows read the index through `lib/vertex_index.glsl`, which on
/// that target is an attribute the backend feeds from a buffer of its own.
///
/// This compiles every vertex stage the manifest names as the OpenGL ES
/// runtime stage a shader bundle carries (`--runtime-stage-gles`, the target
/// that defines `IMPELLER_TARGET_OPENGLES`) with the SDK's own `impellerc`, and
/// reads the source that came out.
///
/// Mutation: write `gl_VertexIndex` back into `MorphColumn` in
/// `lib/morph.glsl`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_impeller/src/gpu_vertex_index.dart';
import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shaders = Directory('../flutter3d_shaders/shaders').absolute.path;
  final manifest =
      jsonDecode(
            File('$shaders/flutter3d.shaderbundle.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  /// [file] compiled for [target], as the text the driver is handed.
  String compiled(String name, String file, String target) {
    final compiler = impellercPath();
    final shaderLib = File(compiler).parent.uri.resolve('shader_lib').path;
    final scratch = Directory.systemTemp.createTempSync('f3d_gles_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final result = Process.runSync(compiler, <String>[
      target,
      '--input=$shaders/$file',
      '--sl=${scratch.path}/$name.glsl',
      '--spirv=${scratch.path}/$name.spv',
      '--include=$shaderLib',
      '--include=$shaders',
      '--input-type=vert',
    ]);
    expect(result.exitCode, 0, reason: '$name: ${result.stderr}');
    // A runtime stage is a flatbuffer with the source inside it as text.
    return latin1.decode(File('${scratch.path}/$name.glsl').readAsBytesSync());
  }

  final vertexStages = <String, String>{
    for (final MapEntry(key: name, value: entry) in manifest.entries)
      if ((entry! as Map<String, Object?>)['type'] == 'vertex')
        name: (entry as Map<String, Object?>)['file']! as String,
  };

  test('the manifest has vertex stages to read', () {
    expect(vertexStages, contains('MeshVertex'));
    expect(vertexStages, contains('MeshInstancedVertex'));
  });

  for (final MapEntry(key: name, value: path) in vertexStages.entries) {
    test('$name reads no built-in index on OpenGL ES', () {
      final glsl = compiled(
        name,
        path.replaceFirst('shaders/', ''),
        '--runtime-stage-gles',
      );
      expect(glsl, isNot(contains('gl_VertexID')));
      expect(glsl, isNot(contains('gl_InstanceID')));
      // What the backend feeds is what the stage declares: an attribute
      // declared and not fed reads nought, one fed and not declared refuses
      // the pipeline.
      expect((
        vertex: glsl.contains(glesVertexIndexAttribute),
        instance: glsl.contains(glesInstanceIndexAttribute),
      ), indexUseOf(name));
    });
  }

  test('a stage that morphs takes the vertex index as an attribute', () {
    final glsl = compiled('MeshVertex', 'mesh.vert', '--runtime-stage-gles');
    expect(glsl, contains(glesVertexIndexAttribute));
  });

  test('a batch takes the instance index as an attribute', () {
    final glsl = compiled(
      'MeshInstancedVertex',
      'mesh_instanced.vert',
      '--runtime-stage-gles',
    );
    expect(glsl, contains(glesVertexIndexAttribute));
    expect(glsl, contains(glesInstanceIndexAttribute));
  });

  test('Metal keeps the built-in and no attribute', () {
    final msl = compiled('MeshVertex', 'mesh.vert', '--metal-desktop');
    expect(msl, isNot(contains(glesVertexIndexAttribute)));
    expect(msl, contains('vertex_id'));
  });
}
