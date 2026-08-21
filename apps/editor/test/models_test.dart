/// The models a template gives a new game, read back by the engine that will
/// draw them.
///
///     flutter test test/models_test.dart
///
/// **This repository could not make a model.** `prepare_models.py` transforms
/// ones somebody downloaded; everything else is built out of primitives at
/// runtime by the game that draws it, which is right for a game and useless to
/// anything that is not that game. `tool/make_models.py` writes real glTF, and
/// this is the only thing that can say whether it wrote it correctly: a `.glb`
/// that will not load is a file the generator was perfectly happy about.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Every model the generator writes, found by looking rather than by a list
/// typed here: a model that stops being generated should fail, not vanish.
List<File> _models() {
  final root = Directory('assets/templates');
  if (!root.existsSync()) return const <File>[];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((File it) => it.path.endsWith('.glb'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

GraphicsDevice _device() => CpuDevice(
      width: 16,
      height: 9,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

void main() {
  final models = _models();

  test('there are models to check at all', () {
    // Otherwise everything below passes by having nothing to say.
    expect(models, hasLength(greaterThanOrEqualTo(6)),
        reason: 'run tool/make_models.py');
  });

  test('and one of them, put in a scene, is something you can see', () async {
    // **Loading is not drawing.** Every check above is satisfied by a file the
    // renderer would show nothing for — a node with no mesh under it, a mesh
    // whose triangles are degenerate, a material the size of a full stop. One
    // model, rendered, against a clear colour it is not.
    final device = _device();
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: SolidColorTexture.white.upload(device),
      fallbackNormal: SolidColorTexture.flatNormal.upload(device),
    );
    final scene = Scene();
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.05,
        near: 0.1,
        far: 100.0,
      ),
    )..setPosition(0.0, 0.0, 2.2);
    camera.lookAt(Vector3.zero());
    scene.add(camera);
    scene.add(LightNode(intensity: 4.0, name: 'sun')
      ..lookAt(Vector3(-0.4, -1.0, -0.6)));

    final document = await decodeModel(
      ModelLoadRequest(source: FileAssetSource(models.first.path)),
    );
    (await ModelAsset.fromDocument(
      document,
      device: device,
      fallbackAlbedo: SolidColorTexture.white.upload(device),
      name: 'one',
    ))
        .instantiate(scene);

    final result = renderer.render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: const RenderSettings(),
    );
    final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();

    var lit = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] > 8 || pixels[i + 1] > 8 || pixels[i + 2] > 8) lit++;
    }
    expect(lit, greaterThan(20),
        reason: '${models.first.path} drew $lit pixels of anything');
  });

  for (final file in models) {
    final name = file.path.split('/').last;

    group(name, () {
      late Uint8List bytes;
      late GltfAsset asset;

      setUpAll(() async {
        bytes = file.readAsBytesSync();
        asset = await GltfLoader().load(bytes);
      });

      test('loads with nothing to complain about', () async {
        // **The single most valuable line here.** Everything the loader forgives
        // and reports rather than throwing goes through this channel: a missing
        // POSITION, a missing NORMAL, a topology it does not draw, an index past
        // the end of its accessor. All of them draw *something*, which is why a
        // file with any of them looks fine until it does not.
        expect(asset.warnings, isEmpty);
        expect(asset.surfaces, isNotEmpty);
        expect(asset.roots, isNotEmpty);
      });

      test('and carries its own normals', () {
        // The loader will invent flat ones for a mesh with none, by de-indexing
        // it — so a generator that forgot them is invisible in the picture and
        // costs every model its vertex sharing.
        for (final surface in asset.surfaces) {
          expect(surface.mesh.layout.floatOffsetOf(VertexLayout.normal.name),
              isNotNull);
        }
      });

      test('and is not made of metal', () {
        // **glTF defaults `metallicFactor` to 1.0 and this engine reads it
        // faithfully.** A material that leaves it out is fully metallic, and a
        // fully metallic thing with no environment map is very nearly black:
        // every model written without that one line looks like a hole in the
        // level.
        for (final material in asset.materials) {
          expect(material.metallic, 0.0,
              reason: 'write metallicFactor explicitly in make_models.py');
        }
      });

      test('and has nothing in it that a template promised not to have', () {
        // No animations, no skins, no textures: a template model is a shape and
        // a colour. Anything else is a file somebody has to have a licence for.
        expect(asset.animations, isEmpty);
        expect(asset.skins, isEmpty);
        expect(asset.images, isEmpty);
      });

      test('and reaches the device the same way a game\'s model does', () async {
        // The path `apps/editor/lib/main.dart` uses for a model a document
        // names, on the software device.
        final device = _device();
        final document = await decodeModel(
          ModelLoadRequest(source: FileAssetSource(file.path)),
        );
        final model = await ModelAsset.fromDocument(
          document,
          device: device,
          fallbackAlbedo: SolidColorTexture.white.upload(device),
          name: file.path,
        );

        final bounds = model.localBounds;
        final size = bounds.max - bounds.min;
        expect(size.x, greaterThan(0.01));
        expect(size.y, greaterThan(0.01));
        // Nothing a template ships is bigger than a room, and a model that came
        // out a hundred times too large is a generator with a units bug.
        expect(size.length, lessThan(6.0),
            reason: '$name is ${size.x} by ${size.y} by ${size.z}');
      });
    });
  }
}
