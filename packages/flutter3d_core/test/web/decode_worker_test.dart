/// The browser's decode worker, run: a model and a panorama decoded off the
/// page, and every way it hands a decode back to be done in place.
///
///     dart test -p chrome test/web/decode_worker_test.dart
///
/// **The worker is compiled the way an application compiles it**, by
/// `dart run flutter3d_core:decode_worker`, from a hybrid isolate on the VM
/// that also reads the sample models off the disk. The script lands under
/// this package's `.dart_tool/`, which the test server serves beside the
/// page.
///
/// **What comes back is held to the in-place decode of the same bytes**, not
/// to a count: the worker answers with an `.f3d`, and a container that
/// dropped a surface, reordered a vertex or lost a node would still be a
/// model.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// Where the hybrid isolate compiles the worker, relative to the package.
const String _script = '.dart_tool/flutter3d_core_test/decode_worker.js';

/// The worker's address as the page resolves it: the server serves the
/// package root two levels above this file's page.
final Uri _scriptUrl = Uri.base.resolve('../../$_script');

/// Compiles the worker and reads the samples, on the VM.
const String _hybrid =
    '''
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final compiled = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'flutter3d_core:decode_worker',
    '$_script',
  ]);
  if (compiled.exitCode != 0) {
    channel.sink.add('\${compiled.stdout}\${compiled.stderr}');
    await channel.sink.close();
    return;
  }
  final samples = <String, List<int>>{
    for (final name in <String>[
      'Box.glb',
      'BoxTextured.glb',
      'cube/Cube.gltf',
      'cube/Cube.bin',
      'teapot.obj',
    ])
      name: File('../flutter3d_samples/assets/\$name').readAsBytesSync(),
  };
  channel.sink.add(samples);
  await channel.sink.close();
}
''';

/// Bytes the page already holds, with siblings from [files].
final class _Bytes extends AssetSource {
  _Bytes(this.key, this.files);

  @override
  final String key;
  final Map<String, Uint8List> files;
  final List<String> asked = <String>[];

  @override
  Future<Uint8List> read(AssetRead request) async => files[key]!;

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    final path = key.contains('/')
        ? '${key.substring(0, key.lastIndexOf('/') + 1)}${request.uri}'
        : request.uri;
    asked.add(path);
    return files[path] ?? (throw StateError('no $path'));
  };
}

late final Map<String, Uint8List> _samples;

Future<void> _compileAndRead() async {
  final reply = await spawnHybridCode(_hybrid).stream.first;
  if (reply is String) fail('the worker did not compile:\n$reply');
  _samples = <String, Uint8List>{
    for (final MapEntry(:key, :value) in (reply! as Map).entries)
      key as String: Uint8List.fromList((value as List).cast<int>()),
  };
}

/// [key] decoded in place and through `decodeModelInIsolate`, which goes to
/// the worker where one is running.
Future<(ModelDocument, ModelDocument)> _bothWays(String key) async {
  final inPlace = await decodeModel(
    ModelLoadRequest(source: _Bytes(key, _samples)),
  );
  final viaLoader = await decodeModelInIsolate(
    ModelLoadRequest(source: _Bytes(key, _samples)),
  );
  return (inPlace, viaLoader);
}

void _expectSame(ModelDocument inPlace, ModelDocument worker) {
  final problems = compareModelDocuments(inPlace, worker);
  expect(problems, isEmpty, reason: problems.join('\n'));
  expect(worker.nodes.length, inPlace.nodes.length);
  expect(worker.roots, inPlace.roots);
  for (var i = 0; i < inPlace.nodes.length; i++) {
    expect(worker.nodes[i].name, inPlace.nodes[i].name);
    expect(worker.nodes[i].children, inPlace.nodes[i].children);
  }
  expect(
    <String?>[for (final m in worker.materials) m.name],
    <String?>[for (final m in inPlace.materials) m.name],
  );
  expect(
    <int>[for (final image in worker.images) image.bytes.length],
    <int>[for (final image in inPlace.images) image.bytes.length],
  );
}

void main() {
  setUpAll(_compileAndRead);
  tearDown(WebDecodeWorker.stop);

  test('without a script a decode runs in place and says why', () async {
    WebDecodeWorker.stop();
    final before = WebDecodeWorker.decoded;
    final (inPlace, viaLoader) = await _bothWays('Box.glb');
    _expectSame(inPlace, viaLoader);
    expect(WebDecodeWorker.decoded, before);
    expect(WebDecodeWorker.inPlaceReason, contains('WebDecodeWorker.use'));
  });

  group('with the worker running', () {
    setUp(() => WebDecodeWorker.use(_scriptUrl));

    test('a GLB is decoded there and is the model decoded here', () async {
      // Mutation: decode in place in `model_isolate_web.dart` — the count of
      // worker decodes stays where it was.
      final before = WebDecodeWorker.decoded;
      final (inPlace, worker) = await _bothWays('BoxTextured.glb');
      expect(WebDecodeWorker.decoded, before + 1);
      expect(WebDecodeWorker.inPlaceReason, isNull);
      _expectSame(inPlace, worker);
    });

    test("a .gltf's sibling files are read by the page for it", () async {
      final source = _Bytes('cube/Cube.gltf', _samples);
      final before = WebDecodeWorker.decoded;
      final worker = await decodeModelInIsolate(
        ModelLoadRequest(source: source),
      );
      expect(WebDecodeWorker.decoded, before + 1);
      expect(source.asked, contains('cube/Cube.bin'));
      final inPlace = await decodeModel(
        ModelLoadRequest(source: _Bytes('cube/Cube.gltf', _samples)),
      );
      _expectSame(inPlace, worker);
    });

    test('an OBJ, with the options of the request', () async {
      final before = WebDecodeWorker.decoded;
      final worker = await decodeModelInIsolate(
        ModelLoadRequest(
          source: _Bytes('teapot.obj', _samples),
          objNormals: ObjNormals.flat,
        ),
      );
      expect(WebDecodeWorker.decoded, before + 1);
      final inPlace = await decodeModel(
        ModelLoadRequest(
          source: _Bytes('teapot.obj', _samples),
          objNormals: ObjNormals.flat,
        ),
      );
      _expectSame(inPlace, worker);
    });

    test('a file the worker cannot read throws what the decoder throws', () {
      // Mutation: turn the worker's failure into a sentence of its own — the
      // caller catches a `StateError` where it wrote `on Gltf…Exception`.
      final broken = <String, Uint8List>{
        'broken.gltf': Uint8List.fromList(utf8.encode('{"asset": ')),
      };
      final inPlace = decodeModel(
        ModelLoadRequest(source: _Bytes('broken.gltf', broken)),
      ).then<Object?>((_) => null, onError: (Object e) => e.runtimeType);
      final viaLoader = decodeModelInIsolate(
        ModelLoadRequest(source: _Bytes('broken.gltf', broken)),
      ).then<Object?>((_) => null, onError: (Object e) => e.runtimeType);
      return Future.wait(<Future<Object?>>[inPlace, viaLoader]).then((types) {
        expect(types[0], isNotNull);
        expect(types[1], types[0]);
        expect(WebDecodeWorker.inPlaceReason, contains('could not read'));
      });
    });

    test('a request with an application decoder stays on the page', () async {
      final before = WebDecodeWorker.decoded;
      await decodeModelInIsolate(
        ModelLoadRequest(
          source: _Bytes('Box.glb', _samples),
          decoders: const <ModelDecoder>[_Never()],
        ),
      );
      expect(WebDecodeWorker.decoded, before);
      expect(WebDecodeWorker.inPlaceReason, contains('application decoder'));
    });

    test('a panorama is convolved there', () async {
      // Mutation: convolve in place in `background_web.dart`.
      final before = WebDecodeWorker.decoded;
      final hdr = Uint8List.fromList(<int>[
        ...utf8.encode('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 4 +X 8\n'),
        for (var i = 0; i < 32; i++) ...<int>[128, 64, 32, 129],
      ]);
      final cube = await EnvironmentMap.fromEncoded(
        FakeBackend(),
        hdr,
        decodeImage: (Uint8List bytes) async => null,
        size: 4,
        levels: 2,
      );
      expect(cube.levels, 2);
      expect(WebDecodeWorker.decoded, before + 1);
      await expectLater(
        EnvironmentMap.fromEncoded(
          FakeBackend(),
          Uint8List.fromList(utf8.encode('#?RADIANCE\nnot a file')),
          decodeImage: (Uint8List bytes) async => null,
        ),
        throwsA(isA<PanoramaFormatException>()),
      );
    });
  });

  test('a script that is not there leaves decodes on the page', () async {
    WebDecodeWorker.use(Uri.base.resolve('../../no_such_worker.js'));
    final before = WebDecodeWorker.decoded;
    final (inPlace, viaLoader) = await _bothWays('Box.glb');
    _expectSame(inPlace, viaLoader);
    expect(WebDecodeWorker.decoded, before);
    expect(WebDecodeWorker.inPlaceReason, contains('no_such_worker.js'));
  });
}

/// A decoder that wants no file, so the built-in one reads it.
final class _Never extends ModelDecoder {
  const _Never();

  @override
  bool handles(ModelProbe probe) => false;

  @override
  Future<ModelDocument> decode(ModelDecodeContext context) =>
      throw UnimplementedError();
}
