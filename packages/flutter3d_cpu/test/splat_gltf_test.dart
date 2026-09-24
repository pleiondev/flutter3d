/// `splat-glTF`: a checked-in `KHR_gaussian_splatting` file, loaded and drawn
/// through the software rasteriser — `C1`.
///
///     dart test test/splat_gltf_test.dart
///
/// The file is `flutter3d_core/test/formats/fixtures/splat/splat_grid.glb`,
/// written by that package's `tool/make_splat_fixture.dart`: nine splats on
/// a grid, red, green and blue by column, under a node that moves them half
/// a metre right and scales them by 0.8, the middle one long and turned a
/// quarter about Z. What this holds is the path from the file to pixels:
/// the loader's cloud, placed by its node through `SplatContributor.node`,
/// lands where the node puts it, in the colours the file declares, with the
/// middle splat standing taller than it is wide.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

void main() {
  test('splat-glTF', () async {
    final asset = await GltfLoader().load(
      File(
        '../flutter3d_core/test/formats/fixtures/splat/splat_grid.glb',
      ).readAsBytesSync(),
    );
    final splat = asset.splats.single;
    final placement = asset.nodes[splat.node];

    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final node = SceneNode(name: 'splats')
      ..setPosition(
        placement.translation.x,
        placement.translation.y,
        placement.translation.z,
      )
      ..setScale(placement.scale.x, placement.scale.y, placement.scale.z);
    final camera = CameraNode()
      ..setPosition(0.5, 0.0, 4.0)
      ..lookAt(Vector3(0.5, 0.0, 0.0));
    final scene = Scene()
      ..ambientIntensity = 0.0
      ..add(node)
      ..add(camera);

    final renderer = Renderer.create(device: device)
      // Mutation: drop `node:` — the cloud draws at the origin at full size,
      // and the columns are no longer where the node puts them.
      ..addContributor(SplatContributor(splat.cloud, node: node));
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(
        tonemap: false,
        bloom: BloomSettings(enabled: false),
      ),
    );
    final frame = device.readHdrPixels(result.frame);

    final viewProjection = camera.viewProjection(_width / _height);
    (int, int) pixelOf(Vector3 world) {
      final clip = viewProjection.transformed(
        Vector4(world.x, world.y, world.z, 1.0),
      );
      return (
        ((clip.x / clip.w * 0.5 + 0.5) * _width).floor(),
        ((0.5 - clip.y / clip.w * 0.5) * _height).floor(),
      );
    }

    Float32List at(int x, int y) => Float32List.sublistView(
      frame,
      (y * _width + x) * 4,
      (y * _width + x) * 4 + 3,
    );

    // Every splat, where the node puts it, in its column's colour.
    for (var i = 0; i < splat.cloud.count; i++) {
      final local = Vector3(
        splat.cloud.centres[i * 3],
        splat.cloud.centres[i * 3 + 1],
        splat.cloud.centres[i * 3 + 2],
      );
      final (x, y) = pixelOf(splat.transform.transformed3(local));
      final rgb = at(x, y);
      final column = i % 3;
      final others = <double>[
        for (var c = 0; c < 3; c++)
          if (c != column) rgb[c],
      ];
      expect(
        rgb[column],
        greaterThan(0.5),
        reason: 'splat $i at ($x, $y) is $rgb',
      );
      for (final other in others) {
        expect(
          rgb[column],
          greaterThan(other + 0.4),
          reason: 'splat $i at ($x, $y) is $rgb',
        );
      }
    }

    // The middle splat stands taller than it is wide: its long axis is X in
    // the file, turned a quarter about Z by its own quaternion.
    final (cx, cy) = pixelOf(splat.transform.transformed3(Vector3.zero()));
    int run(int dx, int dy) {
      var steps = 0;
      while (at(cx + dx * (steps + 1), cy + dy * (steps + 1))[1] > 0.5) {
        steps++;
      }
      return steps;
    }

    final tall = run(0, 1) + run(0, -1);
    final wide = run(1, 0) + run(-1, 0);
    expect(
      tall,
      greaterThan(wide * 2),
      reason: 'the middle splat is $tall pixels tall and $wide wide',
    );
  });
}
