/// The shadow pass and the id pass morph the mesh too.
///
///     flutter test test/morph_passes_test.dart
///
/// **Three passes draw a mesh and all three have to agree what shape it is.**
/// The colour pass is the one anybody looks at, so a shadow cast by the base
/// shape or a pick answered against it is a bug that hides: the model looks
/// right, and its shadow is under where it used to be. That is not
/// hypothetical — the shadow and pick passes were written without the morph
/// binding first time round, and WebGL drew a shadow displaced by 217 pixels
/// while Impeller happened to look fine because a stale binding was still
/// there.
///
/// Each test isolates its pass. The shadow one reads the **shadow map itself**
/// through `RenderSettings.showShadowMap`, so nothing the colour pass draws can
/// account for a difference; the pick one asks about a point the mesh only
/// reaches once it has morphed.
///
/// The first version of the shadow test framed the floor with the caster
/// supposedly out of shot, and a sideways slide walked the cube into the frame:
/// the two pictures differed because the *cube* had moved, and the test passed
/// with the shadow pass drawing the base shape. Moving the caster up until it
/// left the frame took the shadow with it. Reading the map is the version with
/// nothing left to arrange.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// How far the target slides the whole mesh. A translation, deliberately: this
/// asks whether a pass binds the deltas at all, and the arithmetic of blending
/// them is `morph_test.dart`'s question.
const double _slide = 2.5;

MeshData _cube() => CuboidShape(size: Vector3.all(1.4)).build();

MorphTarget _slideTarget(MeshData mesh) => MorphTarget(
  vertexCount: mesh.vertexCount,
  name: 'slide',
  positions: Float32List.fromList(<double>[
    for (var v = 0; v < mesh.vertexCount; v++) ...<double>[_slide, 0.0, 0.0],
  ]),
);

/// A cube that can slide sideways, over a floor, under a light that casts.
({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _scene({
  required double weight,
  required bool frameTheGround,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final base = _cube();
  final source = MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[_slideTarget(base)],
  );

  final packed = MorphTexture.pack(source)!;
  final texture = device.createTextureFromPixels(
    width: packed.width,
    height: packed.height,
    format: TextureFormat.r32g32b32a32Float,
    pixels: packed.bytes,
  );
  expect(texture, isNotNull, reason: 'the deltas would not upload');

  final scene = Scene();
  final cube =
      MeshNode(
          DeviceMesh.upload(device, source),
          Material(name: 'cube', baseColor: Vector4(0.8, 0.5, 0.3, 1.0)),
          name: 'cube',
        )
        ..setPosition(0.0, 2.0, 0.0)
        ..morph = (MorphState(texture: texture!, targetCount: 1)
          ..setWeights(<double>[weight]));
  scene.add(cube);

  scene.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(24.0, 0.2, 24.0)).build(),
        ),
        Material(name: 'ground', baseColor: Vector4(0.75, 0.75, 0.75, 1.0)),
        name: 'ground',
      )
      ..setPosition(0.0, -0.1, 0.0)
      ..castsShadow = false,
  );

  // Straight down, so the shadow lands directly under the cube and a sideways
  // slide moves it by exactly the slide.
  final sun = LightNode(name: 'sun')..castsShadow = true;
  sun.lookAt(Vector3(0.0, -1.0, -0.05));
  scene.add(sun);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 0.9,
      near: 0.1,
      far: 100.0,
    ),
  );
  if (frameTheGround) {
    camera
      ..setPosition(0.0, 6.0, 11.0)
      ..lookAt(Vector3(0.0, 0.0, 0.0));
  } else {
    camera
      ..setPosition(0.0, 2.0, 9.0)
      ..lookAt(Vector3(0.0, 2.0, 0.0));
  }
  scene.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it, {
  RenderSettings settings = const RenderSettings(),
}) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[RenderView(camera: it.camera)],
    settings: settings,
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

int _differing(Uint8List a, Uint8List b, {int tolerance = 8}) {
  var count = 0;
  for (var p = 0; p < _width * _height; p++) {
    final at = p * 4;
    for (var c = 0; c < 3; c++) {
      if ((a[at + c] - b[at + c]).abs() > tolerance) {
        count++;
        break;
      }
    }
  }
  return count;
}

void main() {
  test('the shadow map holds the shape the colour pass drew', () async {
    // The map itself, not the lit frame: what is on screen here is depth as
    // the light saw it, so the only thing that can differ between the two is
    // where the caster was when the shadow pass drew it.
    //
    // Mutation: drop the state from `_bindMorph` in
    // `renderer_shadow_pass.dart` and these two are identical.
    const shadowMap = RenderSettings(showShadowMap: true);
    final rest = await _draw(
      _scene(weight: 0.0, frameTheGround: true),
      settings: shadowMap,
    );
    final slid = await _draw(
      _scene(weight: 1.0, frameTheGround: true),
      settings: shadowMap,
    );

    expect(
      _differing(rest, slid),
      greaterThan(200),
      reason: 'the shadow pass drew the base shape',
    );
  });

  test('a pick lands on the shape the eye sees', () async {
    // The cube starts left of the middle and the target slides it right, so a
    // point to the right of centre is empty until it morphs. Mutation: drop
    // `_bindMorph` from `renderer_pick_pass.dart` and the answers swap — the
    // picture and the id buffer disagree about where the cube is.
    final it = _scene(weight: 1.0, frameTheGround: false);

    // Where that puts it: the camera is nine metres back with a 0.9 radian
    // vertical field of view, so the frame is 2·tan(0.45)·9 ≈ 8.7 metres tall
    // and 11.6 wide at the cube's distance. A cube centred at x = 2.5 sits at
    // 0.5 + 2.5/11.6 ≈ 0.715 across, and is 1.4 metres wide — an eighth of the
    // frame — so the centre is the point to ask about and the edges are not.
    // 0.78 was the first guess and it landed on the silhouette's edge.
    final onIt = it.renderer.pickPixel(0.715, 0.5);
    final behind = it.renderer.pickPixel(0.5, 0.5);
    it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );

    expect(
      (await onIt)?.name,
      'cube',
      reason: 'the id pass did not morph the mesh',
    );
    expect(
      (await behind)?.name,
      isNot('cube'),
      reason: 'the id pass drew the cube where it no longer is',
    );
  });
}
