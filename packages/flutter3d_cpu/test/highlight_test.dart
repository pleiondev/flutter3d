/// The outline is drawn where the thing is.
///
///     flutter test test/highlight_test.dart
///
/// **`RenderSettings.highlighted` had no caller until the editor.** The engine
/// has had the pass since before there was anything to outline — its own doc
/// says "typically whatever picking last selected" — and the first person to
/// use it reported the frame sitting beside the object rather than round it.
///
/// So: draw a box, ask for it to be outlined, and compare where the box's
/// pixels are with where the outline's are.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// The rectangle covered by pixels a test picks out.
({int left, int right, int top, int bottom, int count}) _boundsOf(
  Uint8List rgba,
  bool Function(int r, int g, int b) wanted,
) {
  var left = _width, right = -1, top = _height, bottom = -1, count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (!wanted(rgba[i], rgba[i + 1], rgba[i + 2])) continue;
    final pixel = i ~/ 4;
    final x = pixel % _width;
    final y = pixel ~/ _width;
    left = x < left ? x : left;
    right = x > right ? x : right;
    top = y < top ? y : top;
    bottom = y > bottom ? y : bottom;
    count++;
  }
  return (left: left, right: right, top: top, bottom: bottom, count: count);
}

void main() {
  test('the highlight lands on the thing it highlights', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);

    final scene = Scene();
    // Unlit and white, so "the box" is the brightest thing and needs no light.
    final box = MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build()),
      Material(
        name: 'box',
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
        lighting: LightingModel.unlit,
      ),
      name: 'box',
    )..setPosition(0.0, 0.0, -6.0);
    scene.add(box);

    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.0,
        near: 0.1,
        far: 50.0,
      ),
    );
    camera.lookAt(Vector3(0.0, 0.0, -6.0));
    scene.add(camera);

    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: RenderSettings(highlighted: <SceneNode>[box]),
    );
    final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();

    // The box is white; the outline is `DebugColors.selection`, a green with
    // very little red in it.
    final white = _boundsOf(pixels, (r, g, b) => r > 200 && g > 200 && b > 200);
    final green = _boundsOf(pixels, (r, g, b) => g > 120 && r < 140 && b < 140);

    expect(white.count, greaterThan(500), reason: 'the box was not drawn');
    expect(green.count, greaterThan(20), reason: 'nothing was outlined');

    // The outline goes round the box, so it starts no further in than the box's
    // own edge and no further out than a couple of pixels. Two, because the
    // outline is drawn on the world-space bounds of a box the camera sees in
    // perspective, and the corners of that box project a little outside its
    // silhouette.
    for (final (name, outline, thing) in <(String, int, int)>[
      ('left', green.left, white.left),
      ('top', green.top, white.top),
    ]) {
      expect((outline - thing).abs(), lessThanOrEqualTo(3),
          reason: 'the outline\'s $name edge is at $outline and the box\'s is '
              'at $thing');
    }
    expect((green.right - white.right).abs(), lessThanOrEqualTo(3),
        reason: 'the outline\'s right edge is at ${green.right} and the box\'s '
            'is at ${white.right}');
    expect((green.bottom - white.bottom).abs(), lessThanOrEqualTo(3),
        reason: 'the outline\'s bottom edge is at ${green.bottom} and the '
            'box\'s is at ${white.bottom}');
  });

  test('and a group is outlined by what is under it', () async {
    // **What the editor's marker is**: a holder with twelve thin bars beneath
    // it, not a mesh. The first version of the highlight drew axes a tenth of
    // the *scene* long for anything that was not a `MeshNode` — three enormous
    // lines through the middle of the level where a small box was wanted, which
    // is what "now it started flickering" turned out to be.
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);

    final scene = Scene();
    // Something far away, so a scene-sized axis would be unmistakable.
    scene.add(
      MeshNode(
        DeviceMesh.upload(
            device, CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build()),
        Material(name: 'far', lighting: LightingModel.unlit),
        name: 'far',
      )..setPosition(0.0, 0.0, -60.0),
    );

    final holder = SceneNode(name: 'marker')..setPosition(0.0, 0.0, -6.0);
    holder.add(
      MeshNode(
        DeviceMesh.upload(
            device, CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build()),
        Material(
          name: 'box',
          baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'box',
      ),
    );
    scene.add(holder);

    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.0,
        near: 0.1,
        far: 200.0,
      ),
    );
    camera.lookAt(Vector3(0.0, 0.0, -6.0));
    scene.add(camera);

    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: RenderSettings(highlighted: <SceneNode>[holder]),
    );
    final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();

    final white = _boundsOf(pixels, (r, g, b) => r > 200 && g > 200 && b > 200);
    final green = _boundsOf(pixels, (r, g, b) => g > 120 && r < 140 && b < 140);

    expect(green.count, greaterThan(20), reason: 'the group was not outlined');
    expect((green.left - white.left).abs(), lessThanOrEqualTo(3),
        reason: 'the outline is not round the box under the holder: outline '
            '${green.left}..${green.right}, box ${white.left}..${white.right}');
    expect((green.right - white.right).abs(), lessThanOrEqualTo(3));
  });
}
