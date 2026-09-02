import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';

import '../flutter3d_conformance.dart';

Future<void> checkShaderNames(GraphicsDevice device) async {
  // The one requirement GraphicsDevice cannot express. The engine asks a
  // library for entry points by name, so a backend written from the interface
  // alone compiles, runs, and draws nothing — and the frame that comes back is
  // empty for a reason nothing reports.
  //
  // Named individually rather than counted: "seventeen of twenty-three" sends
  // somebody to diff two lists by hand.
  final missing = <String>[];
  for (final shader in kRequiredShaders) {
    if (device.shaders[shader.name] == null) missing.add(shader.name);
  }
  require(
    missing.isEmpty,
    'the bundle has no ${missing.join(', ')}. Every backend ships its own '
    'bundle and every bundle answers to the same names; see '
    'package:flutter3d_shaders.',
  );
}

Future<void> checkLinking(GraphicsDevice device) async {
  // Compiling is not linking. A stage pair can hold two shaders that each
  // compile and refuse to link together, and the one that fails is not the one
  // that looks wrong.
  //
  // Measured rather than assumed, because the obvious version of this claim is
  // false: a fragment input that is *declared and never read* links fine even
  // with no matching vertex output — the compiler drops it. What does fail is
  // an input the fragment stage actually reads and the vertex stage never
  // writes. Checked by making exactly that mutation and watching this fail.
  //
  // The pairs the engine actually builds, not every combination: a bundle is
  // allowed to hold stages that are never linked together.
  const pairs = <(String, String)>[
    ('MeshVertex', 'Pbr'),
    ('MeshVertex', 'ShadowDepth'),
    ('MeshVertex', 'ShadowDistance'),
    ('MeshSkinnedVertex', 'Pbr'),
    ('MeshInstancedVertex', 'Pbr'),
    ('MeshInstancedVertex', 'ShadowDepth'),
    ('MeshInstancedVertex', 'ShadowDistance'),
    ('MeshLightmappedVertex', 'Pbr'),
    ('MeshLightmappedVertex', 'Lambert'),
    ('ShadowTileResetVertex', 'ShadowTileReset'),
    ('FullscreenVertex', 'Composite'),
    ('DebugLineVertex', 'DebugLine'),
    ('ParticleVertex', 'Particle'),
    // The sky is the only pair where both stages are new at once, so it is the
    // one where a varying can disagree with nothing to compare against. Both
    // pairs, because only one of them is exercised by any given frame.
    //
    // **This table said `SkyVertex` for both, and had stopped being true.** The
    // cube grew a vertex stage of its own when the gradient's vertices changed
    // shape — the gradient carries six colours per vertex now and the cube
    // carries one tint — so `SkyCube` reads a `v_tint` that `SkyVertex` has
    // never written. A browser refuses to link exactly that, which is what this
    // check is for; nothing caught it because these tests only run in a browser
    // and nothing ran them.
    ('SkyVertex', 'Sky'),
    ('SkyCubeVertex', 'SkyCube'),
  ];

  for (final (vertexName, fragmentName) in pairs) {
    final vertex = device.shaders[vertexName];
    final fragment = device.shaders[fragmentName];
    require(
      vertex != null && fragment != null,
      '$vertexName + $fragmentName: one of the stages is missing',
    );
    try {
      device.createPipeline(vertex!, fragment!);
    } catch (error) {
      throw ConformanceFailure(
        '$vertexName + $fragmentName does not link: '
        '$error',
      );
    }
  }
}
