/// `fmt-28`: `ModelLight`/`ModelCamera`, decoded from `KHR_lights_punctual`
/// and glTF's own core `cameras`, and the node fields (`lightIndex`,
/// `cameraIndex`) that say which node points at which. Round-tripped through
/// a handwritten glTF with two light sources and a camera, per the row's own
/// acceptance line.
///
///     dart test test/lights_cameras_test.dart
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

/// A one-triangle glTF with two lights (a point and a spot), a perspective
/// and an orthographic camera, each on its own node — the row's own
/// acceptance shape, built by hand rather than loaded from a sample so every
/// field in it is one this test chose and can check.
Uint8List _handwrittenGltf() {
  final positions = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final buffer = base64Encode(positions.buffer.asUint8List());
  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>['KHR_lights_punctual'],
    'extensions': <String, Object?>{
      'KHR_lights_punctual': <String, Object?>{
        'lights': <Object?>[
          <String, Object?>{
            'name': 'Point',
            'type': 'point',
            'color': <Object?>[1.0, 0.5, 0.25],
            'intensity': 800.0,
            'range': 10.0,
          },
          <String, Object?>{
            'name': 'Spot',
            'type': 'spot',
            'color': <Object?>[0.2, 0.4, 0.6],
            'intensity': 400.0,
            'spot': <String, Object?>{
              'innerConeAngle': 0.1,
              'outerConeAngle': 0.5,
            },
          },
        ],
      },
    },
    'cameras': <Object?>[
      <String, Object?>{
        'name': 'Persp',
        'type': 'perspective',
        'perspective': <String, Object?>{
          'yfov': 0.8,
          'aspectRatio': 1.777,
          'znear': 0.1,
          'zfar': 100.0,
        },
      },
      <String, Object?>{
        'name': 'Ortho',
        'type': 'orthographic',
        'orthographic': <String, Object?>{
          'xmag': 2.0,
          'ymag': 1.5,
          'znear': 0.1,
          'zfar': 50.0,
        },
      },
    ],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0, 1, 2, 3, 4],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0, 'name': 'Mesh'},
      <String, Object?>{
        'name': 'PointNode',
        'extensions': <String, Object?>{
          'KHR_lights_punctual': <String, Object?>{'light': 0},
        },
      },
      <String, Object?>{
        'name': 'SpotNode',
        'extensions': <String, Object?>{
          'KHR_lights_punctual': <String, Object?>{'light': 1},
        },
      },
      <String, Object?>{'name': 'PerspNode', 'camera': 0},
      <String, Object?>{'name': 'OrthoNode', 'camera': 1},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
          },
        ],
      },
    ],
    'accessors': <Object?>[
      <String, Object?>{
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': <Object?>[0, 0, 0],
        'max': <Object?>[1, 1, 0],
      },
    ],
    'bufferViews': <Object?>[
      <String, Object?>{
        'buffer': 0,
        'byteOffset': 0,
        'byteLength': positions.lengthInBytes,
      },
    ],
    'buffers': <Object?>[
      <String, Object?>{
        'byteLength': positions.lengthInBytes,
        'uri': 'data:application/octet-stream;base64,$buffer',
      },
    ],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(document)));
}

void _expectPointLight(ModelLight light) {
  expect(light.name, 'Point');
  expect(light.type, ModelLightType.point);
  expect(light.color.x, closeTo(1.0, 1e-6));
  expect(light.color.y, closeTo(0.5, 1e-6));
  expect(light.color.z, closeTo(0.25, 1e-6));
  expect(light.intensity, closeTo(800.0, 1e-6));
  expect(light.range, closeTo(10.0, 1e-6));
}

void _expectSpotLight(ModelLight light) {
  expect(light.name, 'Spot');
  expect(light.type, ModelLightType.spot);
  expect(light.color.x, closeTo(0.2, 1e-6));
  expect(light.color.y, closeTo(0.4, 1e-6));
  expect(light.color.z, closeTo(0.6, 1e-6));
  expect(light.intensity, closeTo(400.0, 1e-6));
  expect(light.range, isNull);
  expect(light.innerConeAngle, closeTo(0.1, 1e-6));
  expect(light.outerConeAngle, closeTo(0.5, 1e-6));
}

void _expectPerspectiveCamera(ModelCamera camera) {
  expect(camera.name, 'Persp');
  final projection = camera.projection;
  expect(projection, isA<ModelPerspectiveCamera>());
  projection as ModelPerspectiveCamera;
  expect(projection.yfov, closeTo(0.8, 1e-6));
  expect(projection.aspectRatio, closeTo(1.777, 1e-6));
  expect(projection.znear, closeTo(0.1, 1e-6));
  expect(projection.zfar, closeTo(100.0, 1e-6));
}

void _expectOrthographicCamera(ModelCamera camera) {
  expect(camera.name, 'Ortho');
  final projection = camera.projection;
  expect(projection, isA<ModelOrthographicCamera>());
  projection as ModelOrthographicCamera;
  expect(projection.xmag, closeTo(2.0, 1e-6));
  expect(projection.ymag, closeTo(1.5, 1e-6));
  expect(projection.znear, closeTo(0.1, 1e-6));
  expect(projection.zfar, closeTo(50.0, 1e-6));
}

void main() {
  group('a handwritten glTF with two lights and a camera', () {
    test('decodes lights, cameras and which node points at which', () async {
      final document = await GltfLoader().load(_handwrittenGltf());

      expect(document.lights, hasLength(2));
      _expectPointLight(document.lights[0]);
      _expectSpotLight(document.lights[1]);

      expect(document.cameras, hasLength(2));
      _expectPerspectiveCamera(document.cameras[0]);
      _expectOrthographicCamera(document.cameras[1]);

      // Mutation: swap which node index reads `lightIndex`/`cameraIndex`, or
      // always read node 0's — these four lines catch a fixed-index bug that
      // a single-light, single-camera fixture could not.
      expect(document.nodes[1].lightIndex, 0);
      expect(document.nodes[2].lightIndex, 1);
      expect(document.nodes[3].cameraIndex, 0);
      expect(document.nodes[4].cameraIndex, 1);

      // The mesh node and the two light nodes carry no camera; the two
      // camera nodes carry no light. Mutation: drop either null check and a
      // writer that always writes both blocks regardless of index would
      // still pass.
      expect(document.nodes[0].lightIndex, isNull);
      expect(document.nodes[0].cameraIndex, isNull);
      expect(document.nodes[3].lightIndex, isNull);
      expect(document.nodes[1].cameraIndex, isNull);
    });

    test('survives a decode, write, decode round trip', () async {
      final source = await GltfLoader().load(_handwrittenGltf());
      final bytes = GltfWriter(source).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      expect(readBack.lights, hasLength(2));
      _expectPointLight(readBack.lights[0]);
      _expectSpotLight(readBack.lights[1]);

      expect(readBack.cameras, hasLength(2));
      _expectPerspectiveCamera(readBack.cameras[0]);
      _expectOrthographicCamera(readBack.cameras[1]);

      expect(readBack.nodes[1].lightIndex, 0);
      expect(readBack.nodes[2].lightIndex, 1);
      expect(readBack.nodes[3].cameraIndex, 0);
      expect(readBack.nodes[4].cameraIndex, 1);

      // Mutation: forget to register `KHR_lights_punctual` in
      // `extensionsUsed` on write — a stricter reader than this one's own
      // loader would then refuse a file that uses an unlisted extension.
      expect(readBack.warnings, isEmpty);
    });
  });

  group('absences the spec gives meaning to', () {
    test('a perspective camera with no aspectRatio or zfar reads back null, '
        'not a default value', () async {
      final positions = Float32List.fromList(<double>[
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
      ]);
      final buffer = base64Encode(positions.buffer.asUint8List());
      final bare = <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'cameras': <Object?>[
          <String, Object?>{
            'type': 'perspective',
            'perspective': <String, Object?>{'yfov': 0.5, 'znear': 0.05},
          },
        ],
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0, 1],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'mesh': 0},
          <String, Object?>{'camera': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'POSITION': 0},
              },
            ],
          },
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
            'min': <Object?>[0, 0, 0],
            'max': <Object?>[1, 1, 0],
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteOffset': 0,
            'byteLength': positions.lengthInBytes,
          },
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': positions.lengthInBytes,
            'uri': 'data:application/octet-stream;base64,$buffer',
          },
        ],
      };
      final document = await GltfLoader().load(
        Uint8List.fromList(utf8.encode(jsonEncode(bare))),
      );
      final projection =
          document.cameras.single.projection as ModelPerspectiveCamera;
      // Mutation: default `aspectRatio`/`zfar` to a number (e.g. 1.0,
      // 1000.0) instead of leaving them null — a caller that treats this as
      // "follow the viewport" / "infinite far plane" would silently stop
      // doing that.
      expect(projection.aspectRatio, isNull);
      expect(projection.zfar, isNull);

      final bytes = GltfWriter(document).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      final readProjection =
          readBack.cameras.single.projection as ModelPerspectiveCamera;
      // Mutation: write `'aspectRatio': projection.aspectRatio ?? 1.0` —
      // the round trip above would still pass with a fixed aspect ratio;
      // this null check on the far side is what actually catches it.
      expect(readProjection.aspectRatio, isNull);
      expect(readProjection.zfar, isNull);
    });

    test('a spot light with default cone angles round-trips without writing '
        'them', () async {
      final light = ModelLight(type: ModelLightType.spot);
      expect(light.innerConeAngle, 0.0);
      expect(light.outerConeAngle, closeTo(math.pi / 4, 1e-9));

      final document = PlainModelDocument(lights: <ModelLight>[light]);
      final bytes = GltfWriter(document).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      expect(readBack.lights.single.innerConeAngle, 0.0);
      expect(readBack.lights.single.outerConeAngle, closeTo(math.pi / 4, 1e-9));
    });
  });

  group('out-of-range indices are ignored, with a warning', () {
    test('a node camera index past cameras.length becomes null', () async {
      final positions = Float32List.fromList(<double>[
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
      ]);
      final buffer = base64Encode(positions.buffer.asUint8List());
      final bad = <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'mesh': 0, 'camera': 5},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'POSITION': 0},
              },
            ],
          },
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
            'min': <Object?>[0, 0, 0],
            'max': <Object?>[1, 1, 0],
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteOffset': 0,
            'byteLength': positions.lengthInBytes,
          },
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': positions.lengthInBytes,
            'uri': 'data:application/octet-stream;base64,$buffer',
          },
        ],
      };
      final document = await GltfLoader().load(
        Uint8List.fromList(utf8.encode(jsonEncode(bad))),
      );
      // Mutation: pass the out-of-range index through unchecked — a writer
      // handed this document would then emit `"camera": 5` into a file with
      // no camera 5, which is invalid glTF.
      expect(document.nodes.single.cameraIndex, isNull);
      expect(
        document.warnings.any((w) => w.contains('camera 5')),
        isTrue,
        reason: document.warnings.join('\n'),
      );
    });
  });
}
