/// A scan split into clusters draws the same picture as the scan whole, with
/// fewer triangles — `C9`, the `scan-chunks` scene.
///
///     dart test test/scan_chunks_test.dart
///
/// Culling a cluster by the frustum, by its cone or by the occlusion test
/// only ever removes triangles the rasteriser would have clipped, culled as
/// back faces or hidden, and the triangles left keep their order inside each
/// cluster, so the frames are compared byte for byte.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A lumpy sphere of about thirty thousand triangles: what a scan of a stone
/// looks like to the renderer, dense, closed and facing every way.
MeshData _scan() {
  final sphere = const SphereShape(
    radius: 1.0,
    segments: 160,
    rings: 96,
  ).build();
  final vertices = Float32List.fromList(sphere.vertices);
  final stride = sphere.layout.floatsPerVertex;
  for (var o = 0; o < vertices.length; o += stride) {
    final x = vertices[o], y = vertices[o + 1], z = vertices[o + 2];
    final bump =
        1.0 + 0.05 * math.sin(5 * x) * math.sin(4 * y) * math.sin(6 * z);
    vertices[o] = x * bump;
    vertices[o + 1] = y * bump;
    vertices[o + 2] = z * bump;
  }
  return MeshData(
    layout: sphere.layout,
    vertices: vertices,
    indices: sphere.indices,
  );
}

final MeshData _whole = _scan();
final MeshData _split = clusterMesh(
  _whole,
  maxTriangles: 512,
  minTriangles: 128,
);

typedef _Frame = ({Float32List pixels, int triangles});

/// Draws the scan (whole or [split]) from each of [eyes] in turn, through one
/// renderer, so the later frames repack the buffers the first one made.
List<_Frame> _render({
  required bool split,
  required List<Vector3> eyes,
  OcclusionMode occlusion = OcclusionMode.none,
  bool wall = false,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scan = MeshNode(
    DeviceMesh.upload(device, split ? _split : _whole),
    Material(baseColor: Vector4(0.8, 0.75, 0.7, 1.0), roughness: 0.8),
  )..setRotationYawPitchRoll(0.3, 0.1, 0.0);
  final camera = CameraNode();
  final scene = Scene()
    ..add(scan)
    ..add(LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.4, -0.7, 0.0))
    ..add(camera);
  if (wall) {
    // A slab across the left half of the view, between the eye and the scan.
    scene.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.6, 3.0, 0.1)).build(),
          ),
          Material(baseColor: Vector4(0.3, 0.35, 0.4, 1.0)),
        )
        ..occluder = true
        ..setPosition(-0.9, 0.0, 1.4),
    );
  }
  final renderer = Renderer.create(device: device);
  return <_Frame>[
    for (final eye in eyes)
      () {
        camera
          ..setPosition(eye.x, eye.y, eye.z)
          ..lookAt(Vector3(0.2, 0.1, 0.0));
        final result = renderer.render(
          width: _width,
          height: _height,
          scene: scene,
          views: <RenderView>[
            RenderView(
              camera: camera,
              clearColor: Vector4(0.05, 0.05, 0.08, 1.0),
            ),
          ],
          settings: RenderSettings(occlusion: occlusion),
        );
        return (
          pixels: device.readHdrPixels(result.frame),
          triangles: result.triangles,
        );
      }(),
  ];
}

void main() {
  final eyes = <Vector3>[
    // Close enough that the top and bottom of the scan leave the frame.
    Vector3(0.0, 0.2, 2.4),
    Vector3(1.6, 0.6, 1.8),
    Vector3(1.6, 0.6, 1.8),
  ];

  test('scan-chunks: the split scan is the whole scan, fewer triangles', () {
    // Mutation: widen `facesAwayFrom` to cull a cluster whose cone reaches
    // edge-on, or drop the frustum test's world transform, and a rim of
    // triangles goes missing from the split frame.
    final whole = _render(split: false, eyes: eyes);
    final split = _render(split: true, eyes: eyes);
    for (var i = 0; i < eyes.length; i++) {
      expect(split[i].pixels, whole[i].pixels, reason: 'frame $i');
      expect(split[i].triangles, lessThan(whole[i].triangles * 0.7));
    }
    // The last two frames look from the same place, so the second of them
    // draws exactly what the first did, from the buffer it already holds.
    expect(split[2].triangles, split[1].triangles);
  });

  test('scan-chunks: a wall in front hides clusters, not the picture', () {
    final whole = _render(
      split: false,
      eyes: eyes.sublist(0, 1),
      occlusion: OcclusionMode.software,
      wall: true,
    );
    final open = _render(split: true, eyes: eyes.sublist(0, 1), wall: true);
    final hidden = _render(
      split: true,
      eyes: eyes.sublist(0, 1),
      occlusion: OcclusionMode.software,
      wall: true,
    );
    expect(hidden.single.pixels, whole.single.pixels);
    expect(open.single.pixels, whole.single.pixels);
    expect(hidden.single.triangles, lessThan(open.single.triangles));
  });
}
