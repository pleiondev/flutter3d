/// The committed shader ABI is what the shaders are, and a base it lost a
/// line of says which.
///
///     dart test test/shader_abi_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/shader_abi.dart';

void main() {
  test('api/flutter3d_shaders.abi is what the shaders say', () {
    // Mutation: add a member to a block, or an `in` to a vertex stage,
    // without running tool/abi_snapshot.dart, and the file is stale.
    final committed = File('api/flutter3d_shaders.abi').readAsStringSync();
    expect(
      committed,
      shaderAbiSnapshot(Directory.current.path),
      reason: 'run dart run tool/abi_snapshot.dart',
    );
  });

  test('every entry point, block member and vertex input is a line', () {
    final abi = shaderAbiSnapshot(Directory.current.path);
    expect(abi, contains('entry MeshVertex vertex\n'));
    expect(abi, contains('entry PrefixSum compute\n'));
    expect(abi, contains('vertex MeshInstancedVertex in 9 vec4 i_data\n'));
    // Mutation: write samplers by name alone, and a decal slot turned into
    // an array texture keeps its line.
    expect(
      abi,
      contains('stage Pbr sampler environment_texture samplerCube\n'),
    );
    expect(abi, contains('stage Decal sampler decal_texture_0 sampler2D\n'));
    // Mutation: stop writing varyings, and a minor inserting one before
    // `v_instance` moves the location every prebuilt fragment stage reads.
    expect(abi, contains('vertex MeshVertex out 6 vec4 v_instance\n'));
    expect(abi, contains('fragment Pbr in 1 vec3 v_normal\n'));
    expect(abi, contains('fragment Composite in 0 vec2 v_uv\n'));
    expect(abi, contains('fragment Pbr out 1 vec4 frag_surface\n'));
    // Mutation: write formats from the type's name alone, and a packed
    // colour in a minor would keep the `in vec4 color` line.
    expect(abi, contains('vertex MeshVertex format 4 color float32x4\n'));
    // The attribute only Impeller's OpenGL ES target declares is not the
    // ABI every target shares.
    expect(abi, isNot(contains('f3d_vertex_index')));
    expect(
      RegExp(
        r'^stage Pbr block FragInfo member \w+ 0 ',
        multiLine: true,
      ).hasMatch(abi),
      isTrue,
    );
  });

  test('a line the base has and the current lacks is reported', () {
    const base =
        '# header\nentry A vertex\nstage A block B member c 0 16 1 '
        'Vector4\n';
    // Mutation: compare names only and an offset that moved passes.
    expect(
      shaderAbiLost(
        base: base,
        current:
            'entry A vertex\nstage A block B member c 16 16 1 Vector4\n'
            'entry Z fragment\n',
      ),
      <String>['stage A block B member c 0 16 1 Vector4'],
    );
    expect(
      shaderAbiLost(base: base, current: '${base}entry Z fragment\n'),
      isEmpty,
    );
  });
}
