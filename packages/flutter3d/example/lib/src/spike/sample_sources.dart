import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;

import 'scene_source.dart';

/// Where the sample models live at runtime.
///
/// They are assets of the `flutter3d_samples` package rather than of this
/// application, so Flutter addresses them under `packages/<name>/` — and the
/// package says that prefix itself rather than every caller spelling it out.
/// The engine's tests read the same files straight off disk through the other
/// constant beside this one.
const String _samples = kSamplesAsset;

/// Everything the demo can display.
///
/// The glTF entries are Khronos sample assets, and between them they cover the
/// three ways a glTF file can carry its data: a GLB binary chunk, an embedded
/// base64 buffer, and a `.gltf` with external files next to it.
final List<SceneSource> kSources = <SceneSource>[
  ProceduralSource('Cube', CuboidShape(size: Vector3.all(1.0))),
  const ProceduralSource('Sphere', SphereShape(radius: 0.6)),
  const ProceduralSource('Cylinder', CylinderShape(height: 1.2)),
  const ProceduralSource('Cone', ConeShape(radius: 0.6, height: 1.2)),
  const ProceduralSource('Torus', TorusShape()),
  const ProceduralSource('Capsule', CapsuleShape()),
  const ProceduralSource('Disc', DiscShape(innerRadius: 0.2)),
  ProceduralSource('Vase', _vase),
  const ModelFileSource('glb: Box', '$_samples/Box.glb'),
  const ModelFileSource('glb: Textured', '$_samples/BoxTextured.glb'),
  const ModelFileSource('glb: Vtx colors', '$_samples/BoxVertexColors.glb'),
  const ModelFileSource('gltf: Triangle', '$_samples/Triangle.gltf'),
  const ModelFileSource('gltf: Cube + bin', '$_samples/cube/Cube.gltf'),
  // Animated samples. Between them they cover all three glTF interpolations:
  // AnimatedCube is a single looping rotation, BoxAnimated animates a hierarchy
  // so a moving parent has to carry its child, and InterpolationTest exists
  // specifically to show STEP, LINEAR and CUBICSPLINE side by side.
  const ModelFileSource(
    'anim: Cube',
    '$_samples/animated_cube/AnimatedCube.gltf',
  ),
  const ModelFileSource('anim: Box', '$_samples/BoxAnimated.glb'),
  const ModelFileSource(
    'anim: Interpolation',
    '$_samples/InterpolationTest.glb',
  ),
  // Built to catch a wrong bitangent sign: the left half has authored tangents
  // and the right half has none, so a generator that disagrees with the file
  // shows up as the two halves lighting differently.
  // The same model twice: NormalTangentTest supplies no TANGENT and forces the
  // engine to generate one, NormalTangentMirrorTest ships authored tangents for
  // the identical geometry. Rendering both and diffing the two frames is the
  // only direct check that the generator agrees with an authoring tool.
  const ModelFileSource('map: Tangent gen', '$_samples/NormalTangentTest.glb'),
  const ModelFileSource(
    'map: Tangent file',
    '$_samples/NormalTangentMirrorTest.glb',
  ),
  // The Utah teapot: positions and faces only, so its normals are generated.
  const ModelFileSource('obj: Teapot', '$_samples/teapot.obj'),
  // The same three models through the engine's own container. They exist next
  // to their sources on purpose: switching between "obj: Teapot" and
  // "f3d: Teapot" should show the same picture, and the load time in the panel
  // below is the whole argument for the format.
  // Rigged: the mesh is deformed by a skeleton the animation drives, which is
  // two features meeting — the player writes joint transforms and the skin
  // reads them, neither knowing about the other.
  const ModelFileSource('skin: Simple', '$_samples/RiggedSimple.glb'),
  const ModelFileSource('skin: Figure', '$_samples/RiggedFigure.glb'),
  const ModelFileSource(
    'skin: SimpleSkin',
    '$_samples/simple_skin/SimpleSkin.gltf',
  ),
  const ModelFileSource('f3d: Teapot', '$_samples/f3d/teapot.f3d'),
  const ModelFileSource('f3d: Textured', '$_samples/f3d/BoxTextured.f3d'),
  const ModelFileSource('f3d: Animated', '$_samples/f3d/BoxAnimated.f3d'),
  const ModelFileSource('f3d: Rigged', '$_samples/f3d/RiggedFigure.f3d'),

  // Not a conformance asset: a generated model with a base colour, a
  // metallic-roughness map, a normal map and no tangents of its own, which is
  // the combination the material pipeline is least often exercised against.
  const ModelFileSource('maps: Chest', 'assets/models/fantasy_chest.glb'),
];

/// Surface of revolution from an arbitrary profile: a vase silhouette.
///
/// The same generator the rounded primitives delegate to, which is the point of
/// exposing it as a shape rather than hiding it behind them.
final LatheShape _vase = LatheShape(
  name: 'vase',
  segments: 64,
  profile: <Vector2>[
    Vector2(0.0, -0.62),
    Vector2(0.26, -0.62),
    Vector2(0.26, -0.62),
    Vector2(0.30, -0.50),
    Vector2(0.40, -0.28),
    Vector2(0.44, -0.06),
    Vector2(0.38, 0.16),
    Vector2(0.24, 0.32),
    Vector2(0.18, 0.44),
    Vector2(0.20, 0.56),
    Vector2(0.26, 0.62),
  ],
);
