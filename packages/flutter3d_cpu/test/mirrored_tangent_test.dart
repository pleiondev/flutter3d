/// A normal map on a mirrored copy: a node or an instance whose transform has
/// a negative determinant.
///
///     dart test test/mirrored_tangent_test.dart
///
/// The oracle is the mirror applied to the data instead: the same plane with
/// its positions, normals and tangents reflected on the CPU, and the bitangent
/// sign turned with them, drawn through an identity transform. Mirroring by
/// the transform has to draw exactly that. Before the vertex stages folded the
/// determinant's sign into the tangent's w, the green channel of the map came
/// out inverted on the mirrored copy and relief along V lit from the wrong
/// side.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

const int _size = 32;

/// A normal map leaning four ways, with a strong green lean in two of them:
/// a bitangent that points the wrong way lights those from the other side.
TextureHandle _leaningNormals(CpuDevice device) =>
    device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[
          ...<int>[200, 220, 170, 255],
          ...<int>[128, 230, 170, 255],
          ...<int>[60, 128, 190, 255],
          ...<int>[128, 30, 170, 255],
        ]),
      ),
    )!;

/// [mesh] reflected through the plane x = 0, the way a mirroring transform
/// would carry it: x negated on the position, normal and tangent, the
/// bitangent sign turned, and the winding reversed when [rewind] says so.
MeshData _mirroredInX(MeshData mesh, {required bool rewind}) {
  final layout = mesh.layout;
  final stride = layout.floatsPerVertex;
  final position = layout.floatOffsetOf(VertexLayout.position.name);
  final normal = layout.floatOffsetOf(VertexLayout.normal.name);
  final tangent = layout.floatOffsetOf(VertexLayout.tangent.name);
  final vertices = Float32List.fromList(mesh.vertices);
  for (var v = 0; v < mesh.vertexCount; v++) {
    final base = v * stride;
    vertices[base + position] = -vertices[base + position];
    vertices[base + normal] = -vertices[base + normal];
    vertices[base + tangent] = -vertices[base + tangent];
    vertices[base + tangent + 3] = -vertices[base + tangent + 3];
  }
  final indices = Uint32List.fromList(mesh.indices);
  if (rewind) {
    for (var i = 0; i < indices.length; i += 3) {
      final second = indices[i + 1];
      indices[i + 1] = indices[i + 2];
      indices[i + 2] = second;
    }
  }
  return MeshData(layout: layout, vertices: vertices, indices: indices);
}

/// [mesh] with every triangle wound the other way and nothing else changed.
MeshData _rewound(MeshData mesh) {
  final indices = Uint32List.fromList(mesh.indices);
  for (var i = 0; i < indices.length; i += 3) {
    final second = indices[i + 1];
    indices[i + 1] = indices[i + 2];
    indices[i + 2] = second;
  }
  return MeshData(
    layout: mesh.layout,
    vertices: mesh.vertices,
    indices: indices,
  );
}

/// The HDR frame of a two-metre plane seen from above under a low sun, with
/// the plane made by [place]. The sun is below the plane when [fromBelow]
/// says so, to light the back face a mirrored instance shows.
Float32List _render(
  MeshNode Function(CpuDevice device) place, {
  bool fromBelow = false,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 2.0, 0.0)
    ..lookAt(Vector3.zero(), up: Vector3(0.0, 0.0, -1.0));
  final scene = Scene()
    ..add(place(device))
    ..add(camera)
    ..ambientIntensity = 0.25
    ..add(
      LightNode(intensity: 3.0)
        ..setRotationYawPitchRoll(0.4, fromBelow ? 0.7 : -0.7, 0.0),
    );
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  return device.readHdrPixels(result.frame);
}

Material _mapped(CpuDevice device) => Material(
  normal: _leaningNormals(device),
  normalSampler: SamplerOptions.nearestClamp,
  // Both sides drawn, so an instance mirrored inside a batch — whose winding
  // nothing turns — is still in the picture to be compared.
  doubleSided: true,
);

double _largestDifference(Float32List a, Float32List b) {
  var largest = 0.0;
  for (var i = 0; i < a.length; i++) {
    largest = math.max(largest, (a[i] - b[i]).abs());
  }
  return largest;
}

void main() {
  final plane = const PlaneShape(width: 2.0, depth: 2.0).build();

  group('mirrored-tangent-handedness', () {
    test('a node scaled by -1 in x draws the mirrored data', () {
      final byTransform = _render(
        (device) =>
            MeshNode(DeviceMesh.upload(device, plane), _mapped(device))
              ..setScale(-1.0, 1.0, 1.0),
      );
      // The node's winding is turned for a mirror, so the baked copy is
      // rewound to face the same way.
      final byData = _render(
        (device) => MeshNode(
          DeviceMesh.upload(device, _mirroredInX(plane, rewind: true)),
          _mapped(device),
        ),
      );
      final unmirrored = _render(
        (device) => MeshNode(DeviceMesh.upload(device, plane), _mapped(device)),
      );

      // Mutation: dropping `mirrored ? -w : w` from `MeshVertexShader` (the
      // raw w passed through) inverts the map's green channel on the mirrored
      // node and the first expectation fails by the whole lean.
      expect(_largestDifference(byTransform, byData), lessThan(1e-4));
      // And the mirror is a different picture, or the test proves nothing.
      expect(_largestDifference(byTransform, unmirrored), greaterThan(0.05));
    });

    test(
      'an instance mirrored by its own transform draws the mirrored data',
      () {
        final byInstance = _render(
          (device) => InstancedMeshNode(
            DeviceMesh.upload(device, plane),
            _mapped(device),
            capacity: 1,
          )..addInstance(Matrix4.diagonal3Values(-1.0, 1.0, 1.0)),
          fromBelow: true,
        );
        // Nothing turns the winding for one instance, so neither is the baked
        // copy rewound: both show the same face.
        final byData = _render(
          (device) => InstancedMeshNode(
            DeviceMesh.upload(device, _mirroredInX(plane, rewind: false)),
            _mapped(device),
            capacity: 1,
          )..addInstance(Matrix4.identity()),
          fromBelow: true,
        );

        // Mutation: ignoring the instance's determinant in
        // `MeshInstancedVertexShader` fails this by the whole lean.
        expect(_largestDifference(byInstance, byData), lessThan(1e-4));
      },
    );

    test('mirrored twice, by the node and the instance, is not mirrored', () {
      final twice = _render(
        (device) =>
            InstancedMeshNode(
                DeviceMesh.upload(device, plane),
                _mapped(device),
                capacity: 1,
              )
              ..setScale(-1.0, 1.0, 1.0)
              ..addInstance(Matrix4.diagonal3Values(-1.0, 1.0, 1.0)),
        fromBelow: true,
      );
      // The node's mirror turns the winding and the instance's does not turn
      // it back, so the batch shows its back face; the plain copy is rewound
      // to show the same one, and keeps its bitangent sign.
      final plain = _render(
        (device) => InstancedMeshNode(
          DeviceMesh.upload(device, _rewound(plane)),
          _mapped(device),
          capacity: 1,
        )..addInstance(Matrix4.identity()),
        fromBelow: true,
      );

      // Mutation: multiplying by the node's sign alone, or the instance's
      // alone, leaves one flip in and this fails.
      expect(_largestDifference(twice, plain), lessThan(1e-4));
    });
  });
}
