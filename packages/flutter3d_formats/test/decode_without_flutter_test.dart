/// Reading a model with no Flutter SDK anywhere near it.
///
/// **This file is the claim the package makes, run rather than stated.** The
/// decoders were `flutter3d`'s, and `flutter3d` declares `flutter: sdk`, so a
/// program that wanted to read a `.glb` — a modeller's document layer, a tool
/// an agent starts with `dart run`, a service checking an upload — resolved a
/// Flutter SDK it had no use for, or did not resolve at all. `dart test` runs
/// this; `flutter test` is not involved and neither is a binding.
///
/// The fixtures are built here rather than read from `flutter3d_samples`, and
/// that is the same decision one layer down: the samples package declares
/// `flutter: sdk` for its `flutter.assets` block, so depending on it — even to
/// test — would put the SDK back in front of this one. The Khronos models are
/// still read, by `flutter3d`'s suite, which has a Flutter SDK for other
/// reasons.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

/// A model that is already in memory. The two sources this repository ships
/// read Flutter's asset bundle and `dart:io`, and both live in `flutter3d`;
/// what a decoder needs is bytes and a way to ask for a sibling file.
final class _BytesSource extends AssetSource {
  const _BytesSource(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  @override
  String get key => 'memory:$name';

  @override
  Future<Uint8List> read() async => bytes;

  @override
  AssetUriResolver get resolveUri => (request) async {
    if (request.uri.startsWith('data:')) return decodeDataUri(request.uri);
    throw StateError('nothing to resolve "${request.uri}" against');
  };
}

/// One triangle, with its buffer inline as a data URI so nothing is read from
/// a disk that a browser or a container might not have.
Uint8List _triangleGltf() {
  final positions = Float32List.fromList(<double>[
    0, 0, 0, //
    1, 0, 0,
    0, 1, 0,
  ]);
  final buffer = base64Encode(positions.buffer.asUint8List());
  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0, 'name': 'triangle'},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'name': 'Triangle',
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

void main() {
  test(
    'decodeModel reads a glTF document with no Flutter SDK resolved',
    () async {
      final document = await decodeModel(
        ModelLoadRequest(
          source: _BytesSource('triangle.gltf', _triangleGltf()),
        ),
      );

      expect(document.surfaces, hasLength(1));
      expect(document.surfaces.single.mesh.triangleCount, 1);
      expect(document.nodes.map((node) => node.name), contains('triangle'));
    },
  );

  test('a document read here writes the engine\'s own container', () async {
    final document = await decodeModel(
      ModelLoadRequest(source: _BytesSource('triangle.gltf', _triangleGltf())),
    );

    final bytes = F3dWriter(document).write();
    expect(isF3dFile(bytes), isTrue);
    expect(sniffModelFormat(bytes), ModelFormat.f3d);

    final reread = F3dDocument.parse(bytes);
    expect(reread.surfaces.single.mesh.triangleCount, 1);
  });

  test('sniffing tells the three formats apart by their first bytes', () {
    expect(sniffModelFormat(_triangleGltf()), ModelFormat.gltf);
    expect(
      sniffModelFormat(Uint8List.fromList(utf8.encode('v 0 0 0\nv 1 0 0\n'))),
      ModelFormat.obj,
    );
    // 'glTF', which is a GLB container whatever follows it.
    expect(
      sniffModelFormat(Uint8List.fromList(<int>[0x67, 0x6C, 0x54, 0x46, 2])),
      ModelFormat.gltf,
    );
  });
}
