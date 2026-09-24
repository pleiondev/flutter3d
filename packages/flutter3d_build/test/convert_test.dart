import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// A minimal, hand-written triangle — not `flutter3d_samples`'s fixtures, on
/// purpose: that package needs the Flutter SDK for its own `flutter.assets:`
/// entry, and pulling it in here would put the SDK back on this package's own
/// dependency graph, which is exactly what `flatDartPackages` exists to
/// catch. See `test/fixtures/triangle.obj`'s own comment.
const String _fixture = 'test/fixtures/triangle.obj';

void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_convert_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('--help asks for the usage text, not a crash', () async {
    final out = _BufferSink();
    final err = _BufferSink();
    final code = await runConvert(<String>['--help'], out: out, err: err);
    expect(code, 2);
    expect(err.text, contains('Usage: dart run flutter3d_build:convert'));
    expect(err.text, contains('--textures'));
    expect(err.text, contains('--no-mips'));
  });

  test('no arguments at all asks for the usage text too', () async {
    final err = _BufferSink();
    final code = await runConvert(<String>[], err: err);
    expect(code, 2);
    expect(err.text, contains('Usage:'));
  });

  test(
    'a single file converts, and the round trip agrees with the source',
    () async {
      final output = '${scratch.path}/box.f3d';
      final out = _BufferSink();
      final code = await runConvert(<String>[_fixture, '-o', output], out: out);

      expect(code, 0);
      expect(File(output).existsSync(), isTrue);
      expect(out.text, contains('surfaces'));

      final document = F3dDocument.parse(File(output).readAsBytesSync());
      expect(document.surfaces, isNotEmpty);
    },
  );

  test('without -o, the output sits beside the input with .f3d', () async {
    final source = '${scratch.path}/teapot_copy.obj';
    File(_fixture).copySync(source);

    final code = await runConvert(<String>[source], out: _BufferSink());

    expect(code, 0);
    expect(File('${scratch.path}/teapot_copy.f3d').existsSync(), isTrue);
  });

  test(
    'a directory converts every recognised file under it, recursively',
    () async {
      final nested = Directory('${scratch.path}/models/nested')
        ..createSync(recursive: true);
      File(_fixture).copySync('${scratch.path}/models/a.obj');
      File(_fixture).copySync('${nested.path}/b.obj');
      File('${scratch.path}/models/not_a_model.txt').writeAsStringSync('hello');

      final code = await runConvert(<String>[
        '${scratch.path}/models',
      ], out: _BufferSink());

      expect(code, 0);
      expect(File('${scratch.path}/models/a.f3d').existsSync(), isTrue);
      expect(File('${nested.path}/b.f3d').existsSync(), isTrue);
      expect(
        File('${scratch.path}/models/not_a_model.f3d').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'a directory with -o mirrors relative paths into the output root',
    () async {
      Directory('${scratch.path}/src/deep').createSync(recursive: true);
      File(_fixture).copySync('${scratch.path}/src/deep/c.obj');

      final code = await runConvert(<String>[
        '${scratch.path}/src',
        '-o',
        '${scratch.path}/out',
      ], out: _BufferSink());

      expect(code, 0);
      expect(File('${scratch.path}/out/deep/c.f3d').existsSync(), isTrue);
      expect(File('${scratch.path}/src/deep/c.f3d').existsSync(), isFalse);
    },
  );

  test(
    'an unrecognised extension in --textures is a usage error, not a crash',
    () async {
      final err = _BufferSink();
      final code = await runConvert(<String>[
        _fixture,
        '--textures',
        'astc',
      ], err: err);

      expect(code, 2);
      expect(err.text, contains('Usage:'));
    },
  );

  test('--textures auto prints an honest, not silent, note', () async {
    final out = _BufferSink();
    final code = await runConvert(<String>[
      _fixture,
      '-o',
      '${scratch.path}/box.f3d',
      '--textures',
      'auto',
    ], out: out);

    expect(code, 0);
    expect(out.text, contains('--textures auto accepted'));
  });

  test(
    '--textures etc2/bc name a real family and print no such note',
    () async {
      for (final family in <String>['etc2', 'bc', 'none']) {
        final out = _BufferSink();
        await runConvert(<String>[
          _fixture,
          '-o',
          '${scratch.path}/box.f3d',
          '--textures',
          family,
        ], out: out);

        expect(out.text, isNot(contains('--textures')), reason: family);
      }
    },
  );

  /// Writes an 8×8-textured triangle under [scratch] and returns its `.obj`
  /// path — the fixture the two tests below convert.
  String writeTexturedObj() {
    final objPath = '${scratch.path}/textured.obj';
    File(objPath).writeAsStringSync('''
mtllib textured.mtl
v 0.0 0.0 0.0
v 1.0 0.0 0.0
v 0.0 1.0 0.0
vt 0.0 0.0
vt 1.0 0.0
vt 0.0 1.0
usemtl Textured
f 1/1 2/2 3/3
''');
    File('${scratch.path}/textured.mtl').writeAsStringSync('''
newmtl Textured
map_Kd textured.png
''');
    final pngImage = img.Image(width: 8, height: 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        pngImage.setPixelRgb(x, y, (x * 30) & 0xFF, 60, (y * 30) & 0xFF);
      }
    }
    File(
      '${scratch.path}/textured.png',
    ).writeAsBytesSync(img.encodePng(pngImage));
    return objPath;
  }

  test(
    '--no-mips keeps the base level, where the default carries a chain',
    () async {
      // It used to print a note and do nothing, because nothing generated a
      // chain to skip. Something does now, so the flag has to reach it.
      //
      // Mutation: stop handing `options.mips` to `convertOne` — the second file
      // comes out with two levels as well.
      final objPath = writeTexturedObj();
      Future<Ktx2Texture> convert(String name, List<String> extra) async {
        final outPath = '${scratch.path}/$name.f3d';
        final code = await runConvert(<String>[
          objPath,
          '-o',
          outPath,
          '--textures',
          'bc',
          ...extra,
        ]);
        expect(code, 0);
        return Ktx2Texture.parse(
          F3dDocument.parse(
            File(outPath).readAsBytesSync(),
          ).images.single.bytes,
        );
      }

      // 8×8 halves to 4×4, and four is the block: two levels of BC1, four
      // blocks and then one, eight bytes a block.
      final chained = await convert('chained', const <String>[]);
      expect(chained.levels.map((level) => level.lengthInBytes), <int>[32, 8]);

      final single = await convert('single', const <String>['--no-mips']);
      expect(single.levels.map((level) => level.lengthInBytes), <int>[32]);
    },
  );

  test('--textures bc really encodes a referenced image, end to end', () async {
    final objPath = writeTexturedObj();
    final outPath = '${scratch.path}/textured.f3d';
    final code = await runConvert(<String>[
      objPath,
      '-o',
      outPath,
      '--textures',
      'bc',
    ]);
    expect(code, 0);

    final document = F3dDocument.parse(File(outPath).readAsBytesSync());
    expect(document.images, hasLength(1));
    final bytes = document.images.single.bytes;
    expect(isKtx2File(bytes), isTrue);
    final texture = Ktx2Texture.parse(bytes);
    expect(texture.vkFormat, VkFormat.bc1RgbaUNormBlock);
    expect(texture.pixelWidth, 8);
    expect(texture.pixelHeight, 8);
  });

  test('a missing input names the path, not a stack trace', () async {
    final err = _BufferSink();
    final code = await runConvert(<String>[
      '${scratch.path}/nothing_here.glb',
    ], err: err);

    expect(code, 1);
    expect(err.text, contains('No such file or directory'));
  });

  test(
    'a file that is already .f3d refuses rather than corrupting itself',
    () async {
      final f3dPath = '${scratch.path}/already.f3d';
      await runConvert(<String>[_fixture, '-o', f3dPath], out: _BufferSink());

      final err = _BufferSink();
      final code = await runConvert(<String>[f3dPath], err: err);

      expect(code, 1);
      expect(err.text, contains('already a .f3d file'));
    },
  );

  // `C7`: a splat capture becomes a paged tree of levels of detail. The
  // fixture is `flutter3d_core`'s version 4 SPZ, 48 splats, written by the
  // format's reference library.
  test('a splat capture converts to a .f3dsplat beside it', () async {
    final source = '${scratch.path}/capture.spz';
    File('test/fixtures/cloud.spz').copySync(source);
    final out = _BufferSink();

    final code = await runConvert(<String>[source], out: out);

    expect(code, 0);
    final written = File('${scratch.path}/capture.f3dsplat');
    expect(written.existsSync(), isTrue);
    final tree = parseSplatOctree(written.readAsBytesSync());
    expect(tree.leafSplatCount, 48);
    expect(out.text, contains('48 splats'));
  });

  test('a directory walk picks splat captures up too', () async {
    final models = Directory('${scratch.path}/in')..createSync();
    File('test/fixtures/cloud.spz').copySync('${models.path}/cloud.spz');
    File(_fixture).copySync('${models.path}/a.obj');

    final code = await runConvert(<String>[
      models.path,
      '-o',
      '${scratch.path}/out',
    ], out: _BufferSink());

    expect(code, 0);
    expect(File('${scratch.path}/out/cloud.f3dsplat').existsSync(), isTrue);
    expect(File('${scratch.path}/out/a.f3d').existsSync(), isTrue);
  });

  test('a PLY that is not a splat capture refuses and says why', () async {
    final source = '${scratch.path}/mesh.ply';
    File(source).writeAsStringSync(
      'ply\nformat ascii 1.0\nelement vertex 0\nend_header\n',
    );
    final err = _BufferSink();

    final code = await runConvert(<String>[source], err: err);

    expect(code, 1);
    expect(err.text, contains('as a splat capture'));
  });
}

final class _BufferSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Encoding encoding = utf8;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
}
