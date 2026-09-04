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
  //
  // **This list said it held those pairs and held about half of them.** It
  // carried `Pbr` against all four vertex stages and no other lighting model
  // against any, so five of the six models a material may name were linked by
  // nothing here — and `ParticleTextured` and `ParticleMesh`, both of which the
  // engine draws, were absent too. That mattered most on Impeller, which has no
  // parity link test of its own: this table is the only link check that backend
  // runs, so a varying or an output the two ends disagree about had exactly one
  // place left to be caught and was not in it. The web backend's
  // `engine_parity_test.dart` already links the full set in a browser, which is
  // where the shape below comes from.
  //
  // Written as a product rather than as fifty-odd literals, because that is
  // what it is: a material names a lighting model and a mesh arrives under one
  // of four vertex layouts, and every combination of the two is a pipeline
  // `_pipelineFor` will build.
  const meshVertices = <String>[
    'MeshVertex',
    'MeshSkinnedVertex',
    'MeshInstancedVertex',
    'MeshLightmappedVertex',
  ];
  // `LightingModel.builtIn`, by name. Not read from `flutter3d`, which this
  // package deliberately does not depend on — a suite a backend runs cannot
  // need the engine.
  const lightingModels = <String>[
    'Unlit',
    'Lambert',
    'BlinnPhong',
    'Pbr',
    'Toon',
    'Normals',
  ];
  final pairs = <(String, String)>[
    for (final vertex in meshVertices) ...<(String, String)>[
      for (final model in lightingModels) (vertex, model),
      // Every mesh casts, through the layout it already has.
      (vertex, 'ShadowDepth'),
      (vertex, 'ShadowDistance'),
    ],
    // The picking pass draws every mesh again through the stage its layout
    // needs — plain, skinned or instanced; a lightmapped mesh has the plain
    // layout and draws through the plain stage — so the id stage has to link
    // with these three.
    //
    // The x-ray stage reaches the same three, for the same reason. It declares
    // one output where the others declare two, which is the pairing least like
    // the rest of this table and the one most worth linking here.
    for (final vertex in <String>[
      'MeshVertex',
      'MeshSkinnedVertex',
      'MeshInstancedVertex',
    ]) ...<(String, String)>[(vertex, 'ObjectId'), (vertex, 'Xray')],
    ('ShadowTileResetVertex', 'ShadowTileReset'),
    // Every post stage the renderer builds a pipeline for, through the one
    // vertex stage they all share. The probe's convolution reads a cube through
    // it, which no other post pass does, and `MrtProbe` is the stage that
    // decides whether a second colour attachment is honoured at all.
    for (final post in <String>[
      'Composite',
      'Luminance',
      'ProbePrefilter',
      'BloomThreshold',
      'BloomDownsample',
      'BloomUpsample',
      'Reflections',
      'Ssao',
      'MrtProbe',
    ])
      ('FullscreenVertex', post),
    ('DebugLineVertex', 'DebugLine'),
    // Both particle fragment stages, and the mesh particle's own vertex stage,
    // which is the only one in the bundle with a per-instance buffer.
    ('ParticleVertex', 'Particle'),
    ('ParticleVertex', 'ParticleTextured'),
    ('ParticleMeshVertex', 'ParticleMesh'),
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
