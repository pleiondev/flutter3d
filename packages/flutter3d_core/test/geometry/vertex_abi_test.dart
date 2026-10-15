/// The vertex buffers the engine writes are the formats the shader ABI
/// records (`flutter3d_shaders/api/flutter3d_shaders.abi`).
///
///     dart test test/geometry/vertex_abi_test.dart
///
/// The `.abi` writes each engine vertex stage's attribute with the format
/// its buffer carries it in (`vertex MeshVertex format 4 color float32x4`),
/// and the only-grows rule keeps those lines; this holds the layouts that
/// fill the buffers to them, so a colour packed into four bytes in a minor
/// fails here instead of under every `SkinningHook` written against 1.0.
library;

import 'dart:io';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// `vertex <stage> format <index> <name> <format>` lines of [stage], in
/// index order, as (name, format).
List<(String, String)> _formats(String abi, String stage) {
  final lines = <(int, String, String)>[
    for (final m in RegExp(
      '^vertex $stage format (\\d+) (\\w+) (\\w+)\$',
      multiLine: true,
    ).allMatches(abi))
      (int.parse(m.group(1)!), m.group(2)!, m.group(3)!),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return <(String, String)>[for (final (_, name, f) in lines) (name, f)];
}

String _floats(int count) => count == 1 ? 'float32' : 'float32x$count';

void main() {
  final abi = File(
    '../flutter3d_shaders/api/flutter3d_shaders.abi',
  ).readAsStringSync();

  test('the standard and skinned layouts are the mesh stages\' formats', () {
    // Mutation: make `VertexLayout.color` three components, or give
    // `mesh.vert` an attribute the layout does not carry.
    for (final (stage, layout) in <(String, VertexLayout)>[
      ('MeshVertex', VertexLayout.standard),
      ('MeshLightmappedVertex', VertexLayout.standard),
      ('MeshSkinnedVertex', VertexLayout.skinned),
    ]) {
      final formats = _formats(abi, stage);
      expect(
        formats.take(layout.attributes.length).toList(),
        <(String, String)>[
          for (final a in layout.attributes)
            (a.name, _floats(a.componentCount)),
        ],
        reason: stage,
      );
    }
  });

  test('the instanced layout is the instanced stage\'s formats', () {
    // Mutation: carry `i_color` as four bytes in the instance buffer.
    expect(_formats(abi, 'MeshInstancedVertex'), <(String, String)>[
      for (final buffer in MeshVertexLayouts.instanced.buffers)
        for (final a in buffer.attributes) (a.name, a.format.name),
    ]);
  });
}
