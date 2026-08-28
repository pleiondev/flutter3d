import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/model_loader.dart';
import 'package:flutter3d/src/engine/assets/obj/obj.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

const String kSamples = kSamplesPath;

void main() {
  group('format detection', () {
    test('picks the decoder from the extension', () async {
      final teapot = await decodeModel(
        const ModelLoadRequest(source: FileAssetSource('$kSamples/teapot.obj')),
      );
      expect(teapot.triangleCount, 2256);

      final box = await decodeModel(
        const ModelLoadRequest(source: FileAssetSource('$kSamples/Box.glb')),
      );
      expect(box.surfaces, hasLength(1));
    });

    test('an explicit format overrides the extension', () async {
      // A GLB named .obj would otherwise go to the wrong decoder; the override is
      // the escape hatch for content that does not match its name.
      await expectLater(
        decodeModel(
          const ModelLoadRequest(
            source: FileAssetSource('$kSamples/teapot.obj'),
            format: ModelFormat.gltf,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('sniffs GLB by its magic', () {
      final glb = Uint8List.fromList(<int>[0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]);
      expect(sniffModelFormat(glb), ModelFormat.gltf);
    });

    test('sniffs .gltf JSON past leading whitespace', () {
      final json = Uint8List.fromList(utf8.encode('\n\t  {"asset":{}}'));
      expect(sniffModelFormat(json), ModelFormat.gltf);
    });

    test('falls back to OBJ for plain text', () {
      final obj = Uint8List.fromList(utf8.encode('# teapot\nv 0 0 0\n'));
      expect(sniffModelFormat(obj), ModelFormat.obj);
    });

    test('an empty file does not crash the sniffer', () {
      expect(sniffModelFormat(Uint8List(0)), ModelFormat.obj);
    });
  });

  group('sources', () {
    test('the cache key distinguishes backend and path', () {
      expect(
        const FileAssetSource('a/b.obj').key,
        isNot(const BundleAssetSource('a/b.obj').key),
      );
      expect(const FileAssetSource('a/b.obj').fileName, 'b.obj');
      expect(const BundleAssetSource('x/y/z.glb').fileName, 'z.glb');
    });

    test('a file source resolves siblings from its own directory', () async {
      // The .gltf-with-external-.bin case, which only works if the resolver is
      // scoped to the document's directory.
      final document = await decodeModel(
        const ModelLoadRequest(
          source: FileAssetSource('$kSamples/cube/Cube.gltf'),
        ),
      );
      expect(document.surfaces, isNotEmpty);
      expect(document.triangleCount, greaterThan(0));
    });

    test('a sibling reference cannot escape the directory', () async {
      final resolve = const FileAssetSource(
        '$kSamples/cube/Cube.gltf',
      ).resolveUri;
      await expectLater(
        resolve('../../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(resolve('/etc/passwd'), throwsA(isA<ArgumentError>()));
      await expectLater(
        resolve('https://example.com/x.bin'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a data URI is handled without touching the filesystem', () async {
      final resolve = const FileAssetSource(
        '$kSamples/nowhere.gltf',
      ).resolveUri;
      final bytes = await resolve('data:application/octet-stream;base64,AQID');
      expect(bytes, <int>[1, 2, 3]);
    });
  });

  group('options reach the decoder', () {
    test('objNormals is honoured', () async {
      final smooth = await decodeModel(
        const ModelLoadRequest(
          source: FileAssetSource('$kSamples/teapot.obj'),
          objNormals: ObjNormals.smooth,
        ),
      );
      final flat = await decodeModel(
        const ModelLoadRequest(
          source: FileAssetSource('$kSamples/teapot.obj'),
          objNormals: ObjNormals.flat,
        ),
      );

      // Flat shading de-indexes, so it always produces more vertices.
      expect(flat.vertexCount, greaterThan(smooth.vertexCount));
      expect(flat.triangleCount, smooth.triangleCount);
    });
  });

  group('isolate decoding', () {
    test('produces the same result as decoding in place', () async {
      // The point of the isolate is only *where* the work happens; the output must
      // be identical, including across the copy back over the boundary.
      const request = ModelLoadRequest(
        source: FileAssetSource('$kSamples/teapot.obj'),
      );

      final local = await decodeModel(request);
      final remote = await decodeModelInIsolate(request);

      expect(remote.surfaces.length, local.surfaces.length);
      expect(remote.vertexCount, local.vertexCount);
      expect(remote.triangleCount, local.triangleCount);
      expect(remote.warnings, local.warnings);

      // Vertex data must survive the transfer byte for byte.
      final a = local.surfaces.first.mesh;
      final b = remote.surfaces.first.mesh;
      expect(b.vertices.length, a.vertices.length);
      for (var i = 0; i < a.vertices.length; i += 97) {
        expect(b.vertices[i], a.vertices[i], reason: 'float $i');
      }
      expect(b.indices, a.indices);
    });

    test('materials and bounds survive the boundary', () async {
      const request = ModelLoadRequest(
        source: FileAssetSource('$kSamples/BoxTextured.glb'),
      );
      final remote = await decodeModelInIsolate(request);

      expect(remote.materials, isNotEmpty);
      expect(remote.materials.first.baseColorTexture, isNotNull);
      // The embedded PNG has to arrive intact, or the texture upload gets garbage.
      expect(remote.images.first.bytes.sublist(0, 4), <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
      ]);

      final bounds = remote.computeBounds();
      expect(bounds.max.x, greaterThan(bounds.min.x));
    });

    test('an error in the isolate surfaces to the caller', () async {
      await expectLater(
        decodeModelInIsolate(
          const ModelLoadRequest(
            source: FileAssetSource('$kSamples/does-not-exist.obj'),
          ),
        ),
        throwsA(anything),
      );
    });

    test('several models decode concurrently', () async {
      final documents = await Future.wait(<Future<Object>>[
        decodeModelInIsolate(
          const ModelLoadRequest(
            source: FileAssetSource('$kSamples/teapot.obj'),
          ),
        ),
        decodeModelInIsolate(
          const ModelLoadRequest(source: FileAssetSource('$kSamples/Box.glb')),
        ),
        decodeModelInIsolate(
          const ModelLoadRequest(
            source: FileAssetSource('$kSamples/BoxVertexColors.glb'),
          ),
        ),
      ]);
      expect(documents, hasLength(3));
    });
  });
}
