/// The note, drawn, with writing on it.
///
///     flutter test test/note_render_test.dart
///
/// **A note is read, not drawn** — the game turns one into a line of text and
/// never puts a page in the world — so the only picture of one that exists is
/// the model the editor shows, and until today it was a blank tan rectangle.
/// A blank rectangle in an editor reads as a card, a plaque or a piece of
/// wood; what makes it a note is that there is writing on it.
///
/// The writing is a texture, which is the first one `tool/make_models.py` has
/// ever produced: it wrote positions, normals and colours and said so at the
/// top of the file. What this checks is the whole path — a PNG generated in
/// Python, embedded in a GLB, read by the loader, sampled by a shader — by
/// rendering it and counting paper against ink.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the note draws with its writing on it', () async {
    const width = 160;
    const height = 200;
    final device = CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);

    final document = await GltfLoader()
        .load(File('assets/models/note.glb').readAsBytesSync());
    final asset = await ModelAsset.fromDocument(document, device: device);
    final scene = Scene();
    asset.instantiate(scene, name: 'note');

    scene.add(
      LightNode(color: Vector3(1.0, 1.0, 1.0), intensity: 3.0)
        ..lookAt(Vector3(-0.2, -0.4, -1.0)),
    );
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 0.8,
        near: 0.05,
        far: 10.0,
      ),
    )..setPosition(0.0, 0.0, 0.8);
    camera.lookAt(Vector3(0.0, 0.0, 0.0));
    scene.add(camera);

    final result = renderer.render(
      width: width,
      height: height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.2, 1.0)),
      ],
      settings: const RenderSettings(),
    );
    final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();
    File('/tmp/note_render.png').writeAsBytesSync(
      encodePng(pixels, width, height),
    );

    // Paper is pale and warm; ink is dark and warm; the background is blue.
    // Both halves of the page have to be on screen, because a page with no
    // writing is a card and a page that is all writing is a mistake.
    var paper = 0;
    var ink = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      if (b >= r) continue; // the blue behind it
      if (r > 150 && g > 120) paper++;
      if (r < 130 && g < 120) ink++;
    }

    expect(paper, greaterThan(2000), reason: 'no page: $paper pale pixels');
    expect(ink, greaterThan(60), reason: 'no writing on it: $ink dark pixels');
    expect(ink, lessThan(paper ~/ 2),
        reason: 'the page is more ink than paper, which is not writing');
  });
}
