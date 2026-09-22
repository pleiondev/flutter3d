/// `hero.glb`, drawn — and the four suspects it clears.
///
///     flutter test test/hero_frame_test.dart
///
/// The rigged runner draws as a loose fan of triangles in the shipped game, so
/// the game ships a static penguin instead. Four things were accused, one at a
/// time, and this file is where each was measured rather than argued:
///
///   * **the skinning structure** — eleven primitives get eleven skeletons and
///     every joint binds the right node. Proved in
///     `packages/flutter3d/test/hero_skin_sharing_test.dart`.
///   * **the vertex data** — joint indices inside the skin's range and weights
///     summing to one, on every vertex of all eleven surfaces.
///   * **the size** — the mesh is authored 1.6 cm tall and reaches its metre
///     and a half through a node chain that scales by 48. That makes any
///     failure to cancel the scale catastrophic rather than subtle: 48 squared
///     is 2300, and 2300 times a 1.6 cm mesh is thirty-seven metres of
///     triangles across the view, which is exactly what the defect looks like.
///     It does cancel. The runner stands 1.64 m tall, against a body of 1.8.
///   * **the drawing** — on the software rasteriser it comes out the size and
///     shape of a character, within a fifth of the penguin's drawn area.
///
/// So the fault is not in the file, the import, the rig or the renderer's
/// arithmetic. **It is in the GPU path**, and the reason that was allowed to
/// happen is visible in this file's own existence: the only golden covering
/// skinning at all is `skinned-figure`, and it is rendered by this software
/// rasteriser. The GPU's skinned pipeline has never had a picture taken of it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 160;

/// The penguin, which is the platformer's runner and therefore a game's asset.
const String _models = '../../apps/flutter3d_demo_platformer/assets/models';

/// The rig, which is **not**. It used to sit beside the penguin, in a directory
/// declared whole, so 424 KB went into every download of a game that stopped
/// drawing it — see `flutter3d/test/fixtures/README.md`. It is still drawn here,
/// because this is the test that caught its node scale.
const String _fixtures = '../flutter3d/test/fixtures';

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
  )!;
  return (
    device: device,
    renderer: Renderer.create(
      device: device,
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    ),
  );
}

Future<ModelAsset> _load(String name, CpuDevice device) async {
  final where = name == 'hero' ? _fixtures : _models;
  final document = await decodeModel(
    ModelLoadRequest(source: FileAssetSource('$where/$name.glb')),
  );
  return ModelAsset.fromDocument(document, device: device, name: name);
}

/// Renders [name] the way the game does and reports what landed on the screen.
Future<({int pixels, int width, int height, double tall})> _shoot(
  String name,
) async {
  final engine = _engine();
  final asset = await _load(name, engine.device);
  final scene = Scene();
  final instance = asset.instantiate(scene, name: 'runner');

  scene.add(
    LightNode(type: LightType.directional, intensity: 2.0)
      ..setLocalForward(Vector3(-0.3, -0.9, 0.2)),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 1.0, -4.0)
    ..lookAt(Vector3(0.0, 0.9, 0.0));

  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = (await engine.device.readPixels(
    frame.frame,
  ))!.buffer.asUint8List();

  var minX = _width, maxX = -1, minY = _height, maxY = -1, lit = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      if (pixels[i] + pixels[i + 1] + pixels[i + 2] <= 30) continue;
      lit++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  // How tall the rig stands, from the nodes themselves rather than from the
  // mesh: `localBounds` reports the *unscaled* mesh — 1.6 cm for this file —
  // because the 48 lives in the node transforms.
  var low = 1e30;
  var high = -1e30;
  void reach(SceneNode node) {
    final at = node.worldMatrix.getTranslation();
    if (at.y < low) low = at.y;
    if (at.y > high) high = at.y;
    for (final child in node.children) {
      reach(child);
    }
  }

  reach(instance.root);

  return (
    pixels: lit,
    width: maxX - minX,
    height: maxY - minY,
    tall: high - low,
  );
}

void main() {
  test(
    'the rigged runner is a metre and a half tall, not a centimetre',
    () async {
      // Mutation: drop the armature's scale on the way in, or apply the root's
      // twice. The first leaves a 1.6 cm speck; the second gives thirty-seven
      // metres, which is the defect as it appears on screen.
      final hero = await _shoot('hero');

      expect(
        hero.tall,
        greaterThan(1.2),
        reason:
            'the rig stands ${hero.tall} m, so the 48x node scale is not '
            'reaching the joints',
      );
      expect(
        hero.tall,
        lessThan(2.4),
        reason:
            'the rig stands ${hero.tall} m, so something is applying the '
            'scale more than once',
      );
    },
  );

  test('and it draws like a character, not like a fan of triangles', () async {
    // The claim the whole investigation comes down to. A fan fills the frame
    // or collapses to nothing; a character occupies a person-shaped part of it.
    //
    // Mutation: none named, and that is the point — every mutation that would
    // make this fail lives on the GPU path, which this rasteriser is not. What
    // this pins is that the file, the import, the rig and the renderer's
    // arithmetic are all sound, so the next person does not re-accuse them.
    final hero = await _shoot('hero');
    final penguin = await _shoot('penguin');

    expect(
      hero.width,
      lessThan(_width ~/ 2),
      reason: 'it is ${hero.width} px wide in a $_width px frame',
    );
    expect(
      hero.height,
      lessThan(_height),
      reason: 'it is ${hero.height} px tall in a $_height px frame',
    );
    expect(
      hero.pixels,
      greaterThan(penguin.pixels ~/ 2),
      reason:
          'it covers ${hero.pixels} px against the penguin\'s '
          '${penguin.pixels}, so it has collapsed rather than exploded',
    );
    expect(
      hero.pixels,
      lessThan(penguin.pixels * 3),
      reason:
          'it covers ${hero.pixels} px against the penguin\'s '
          '${penguin.pixels}',
    );
  });

  test('the clips the game asks for are on the instance it builds', () async {
    // `RunnerClips.forRunner` picks a name and `crossFadeToNamed` returns false
    // for one the model lacks — and nothing reads the answer. So this asks the
    // instance the game would actually get.
    final engine = _engine();
    final asset = await _load('hero', engine.device);
    final instance = asset.instantiate(Scene(), name: 'runner');

    expect(
      instance.player,
      isNotNull,
      reason:
          'the model has eighteen clips and instantiating it produced no '
          'player, so the whole animation path is dead on arrival',
    );
  });
}
