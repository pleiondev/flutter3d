import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_models/src/storage/blob_store.dart';
import 'package:flutter3d_models/src/storage/inspect.dart';
import 'package:test/test.dart';

Uint8List _text(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  group('inspectUpload', () {
    test('an OBJ triangle is accepted, and counted from the file', () async {
      final result = await inspectUpload(
        _text('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'),
        fileName: 'triangle.obj',
      );
      expect(result, isA<Accepted>());
      final accepted = result as Accepted;
      expect(accepted.format, SourceFormat.obj);
      expect(accepted.triangleCount, 1);
    });

    test('a GLB renamed to .obj is still read by its bytes', () async {
      // Four bytes of GLB magic and nothing else: the point is which decoder is
      // chosen, and that decoder refuses it in its own words.
      final result = await inspectUpload(
        Uint8List.fromList([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]),
        fileName: 'renamed.obj',
      );
      expect(result, isA<Rejected>());
    });

    test('an empty file is refused', () async {
      expect(
        await inspectUpload(Uint8List(0), fileName: 'empty.glb'),
        isA<Rejected>(),
      );
    });

    test(
      'text that is not a model is refused rather than stored empty',
      () async {
        final result = await inspectUpload(
          _text('Dear diary, today I uploaded a letter instead of a model.'),
          fileName: 'diary.obj',
        );
        expect(result, isA<Rejected>());
        expect((result as Rejected).because, contains('nothing in diary.obj'));
      },
    );

    test(
      'a .gltf that needs a file beside it is refused, and says why',
      () async {
        final gltf = jsonEncode({
          'asset': {'version': '2.0'},
          'buffers': [
            {'uri': 'triangle.bin', 'byteLength': 36},
          ],
          'bufferViews': [
            {'buffer': 0, 'byteLength': 36},
          ],
          'accessors': [
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 3,
              'type': 'VEC3',
              'min': [0, 0, 0],
              'max': [1, 1, 0],
            },
          ],
          'meshes': [
            {
              'primitives': [
                {
                  'attributes': {'POSITION': 0},
                },
              ],
            },
          ],
          'nodes': [
            {'mesh': 0},
          ],
          'scenes': [
            {
              'nodes': [0],
            },
          ],
        });
        final result = await inspectUpload(
          _text(gltf),
          fileName: 'external.gltf',
        );
        expect(result, isA<Rejected>());
        expect((result as Rejected).because, contains('separate file'));
      },
    );

    test('a flutter3d project is accepted as a project', () async {
      final result = await inspectUpload(
        writeProject(const ModelProject()),
        fileName: 'scene.f3dproj',
      );
      expect(result, isA<Accepted>());
      expect((result as Accepted).format, SourceFormat.project);
    });

    test(
      'a damaged project is refused with the reader\'s own sentence',
      () async {
        final bytes = writeProject(const ModelProject());
        final truncated = Uint8List.sublistView(bytes, 0, 14);
        final result = await inspectUpload(truncated, fileName: 'cut.f3dproj');
        expect(result, isA<Rejected>());
      },
    );
  });

  group('titleFromFileName', () {
    test('drops the format suffix and keeps the rest', () {
      expect(titleFromFileName('old_oak-chair.v2.glb'), 'old oak chair.v2');
      expect(titleFromFileName('C:\\models\\lamp.obj'), 'lamp');
      expect(titleFromFileName('.glb'), '.glb');
      expect(titleFromFileName(''), 'Untitled model');
    });
  });

  group('MemoryBlobStore', () {
    test('stores by content, so the same bytes are one blob', () async {
      final store = MemoryBlobStore();
      final a = await store.put(_text('cube'));
      final b = await store.put(_text('cube'));
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.length, 1);
      expect(await store.sizeOf(a), 4);
    });
  });
}
