/// `N7`: one `.f3d` per device class, each cut to its own budget, and a
/// project that names no classes building exactly what it built before.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// A textured sphere of a few thousand triangles: OBJ, its material and a
/// 64x64 texture, so every lever a budget pulls has something to pull.
void _writeTexturedSphere(Directory into) {
  into.createSync(recursive: true);
  final mesh = const SphereShape(
    radius: 1,
    segments: 24,
    rings: 16,
  ).build(layout: VertexLayout.standard);
  final stride = mesh.layout.floatsPerVertex;
  final obj = StringBuffer()
    ..writeln('mtllib sphere.mtl')
    ..writeln('usemtl skin');
  for (var v = 0; v < mesh.vertexCount; v++) {
    final at = v * stride;
    obj
      ..writeln(
        'v ${mesh.vertices[at]} ${mesh.vertices[at + 1]} '
        '${mesh.vertices[at + 2]}',
      )
      ..writeln('vt ${mesh.vertices[at + 6]} ${mesh.vertices[at + 7]}');
  }
  for (var t = 0; t < mesh.indices.length; t += 3) {
    final a = mesh.indices[t] + 1;
    final b = mesh.indices[t + 1] + 1;
    final c = mesh.indices[t + 2] + 1;
    obj.writeln('f $a/$a $b/$b $c/$c');
  }
  File('${into.path}/sphere.obj').writeAsStringSync(obj.toString());
  File(
    '${into.path}/sphere.mtl',
  ).writeAsStringSync('newmtl skin\nKd 1 1 1\nmap_Kd skin.png\n');
  final texture = img.Image(width: 64, height: 64);
  for (final pixel in texture) {
    pixel
      ..r = pixel.x * 4
      ..g = pixel.y * 4
      ..b = 128
      ..a = 255;
  }
  File('${into.path}/skin.png').writeAsBytesSync(img.encodePng(texture));
}

/// What a budget changed in one written file: how many levels its drawn node
/// carries, whether the last is an impostor, and the widest side of each
/// image in it.
({int levels, bool impostor, List<int> sides}) _measure(String path) {
  final document = F3dDocument.parse(File(path).readAsBytesSync());
  final node = document.nodes.singleWhere((n) => n.surfaces.isNotEmpty);
  return (
    levels: node.lods.length,
    impostor: node.lods.isNotEmpty && node.lods.last.impostor != null,
    sides: <int>[
      for (final image in document.images) img.decodeImage(image.bytes)!.width,
    ]..sort(),
  );
}

IOSink _quiet([StringBuffer? into]) {
  final controller = StreamController<List<int>>();
  controller.stream.listen((chunk) => into?.write(utf8.decode(chunk)));
  return IOSink(controller);
}

/// The bakes here run on the software rasteriser, and a loaded machine takes
/// minutes over them. On the tests themselves rather than on the library: a
/// runner that folds every file into one drops a library's `@Timeout`.
const Timeout _slow = Timeout(Duration(minutes: 5));

void main() {
  group('the manifest', () {
    test('names no classes by default', () {
      expect(AssetManifest.parse('rules: []').classes, isEmpty);
      expect(AssetManifest.empty.classes, isEmpty);
    });

    test('a list takes the presets', () {
      final manifest = AssetManifest.parse('classes: [phone, web, desktop]');
      expect(manifest.classes, <DeviceClassBudget>[
        DeviceClassBudget.phone,
        DeviceClassBudget.web,
        DeviceClassBudget.desktop,
      ]);
      expect(manifest.rules, isEmpty);
    });

    test('a mapping changes the numbers it names and keeps the rest', () {
      final manifest = AssetManifest.parse('''
classes:
  phone:
    maxTextureSide: 256
    lods: [0.3]
  desktop:
''');
      final phone = manifest.classes.first;
      expect(phone.deviceClass, DeviceClass.phone);
      expect(phone.textures.maxSide, 256);
      expect(phone.lods, <double>[0.3]);
      expect(phone.impostor, isTrue);
      expect(phone.impostorCell, DeviceClassBudget.phone.impostorCell);
      expect(manifest.classes.last, same(DeviceClassBudget.desktop));
    });

    test('an unknown class, key or a class named twice names its line', () {
      expect(
        () => AssetManifest.parse('classes: [phone, console]'),
        throwsA(
          isA<ManifestFormatException>()
              .having((e) => e.line, 'line', 1)
              .having((e) => e.message, 'message', contains('console')),
        ),
      );
      expect(
        () => AssetManifest.parse('classes:\n  phone:\n    tris: 3\n'),
        throwsA(
          isA<ManifestFormatException>().having((e) => e.line, 'line', 3),
        ),
      );
      expect(
        () => AssetManifest.parse('classes: [web, web]'),
        throwsA(isA<ManifestFormatException>()),
      );
    });
  });

  test('a native build carries the phone and desktop files, a web build the '
      "web's alone", () {
    for (final os in <OS>[OS.macOS, OS.windows, OS.linux, OS.android, OS.iOS]) {
      expect(deviceClassesForTargetOS(os), <DeviceClass>[
        DeviceClass.phone,
        DeviceClass.desktop,
      ], reason: '$os');
    }
    expect(deviceClassesForTargetOS(null), <DeviceClass>[DeviceClass.web]);
    expect(parseDeviceClasses('web, phone'), <DeviceClass>[
      DeviceClass.web,
      DeviceClass.phone,
    ]);
    expect(parseDeviceClasses(<Object?>['desktop']), <DeviceClass>[
      DeviceClass.desktop,
    ]);
    expect(parseDeviceClasses('phone,tv'), isNull);
  });

  group('a build', () {
    late Directory project;
    late String generated;
    setUp(() {
      project = Directory.systemTemp.createTempSync('f3d_classes_');
      _writeTexturedSphere(Directory('${project.path}/assets_src'));
      generated = '${project.path}/flutter3d_generated';
    });
    tearDown(() => project.deleteSync(recursive: true));

    void manifest(String text) =>
        File('${project.path}/flutter3d_assets.yaml').writeAsStringSync(text);

    test('the three files differ as their budgets say', () async {
      manifest('''
classes:
  phone:
    maxTextureSide: 16
    impostorCell: 8
  web:
    maxTextureSide: 32
    impostorCell: 4
  desktop:
''');
      final report = await runAssetBuild(project, log: _quiet());
      expect(report.converted, hasLength(1));

      final phone = _measure('$generated/sphere.phone.f3d');
      final web = _measure('$generated/sphere.web.f3d');
      final desktop = _measure('$generated/sphere.desktop.f3d');
      expect(File('$generated/sphere.f3d').existsSync(), isFalse);

      // Phone: three mesh levels and an impostor (cells kept small here only
      // because a bake on the software rasteriser is slow), the texture
      // fitted to 16.
      expect(phone.levels, 4);
      expect(phone.impostor, isTrue);
      expect(phone.sides, <int>[16, 8 * 8, 8 * 8]);
      // Web: two levels and an impostor, the texture fitted to 32.
      expect(web.levels, 3);
      expect(web.impostor, isTrue);
      expect(web.sides, <int>[4 * 8, 4 * 8, 32]);
      // Desktop: the source's own mesh and texture, as a build without
      // classes writes them.
      expect(desktop.levels, 0);
      expect(desktop.impostor, isFalse);
      expect(desktop.sides, <int>[64]);

      // The same budgets again convert nothing.
      final again = await runAssetBuild(project, log: _quiet());
      expect(again.converted, isEmpty);
      expect(again.skipped, hasLength(1));
    });

    test('a web build bundles only the web file, and removes what an '
        'earlier build left', () async {
      manifest(
        'classes:\n  phone: {impostor: false, lods: [0.5]}\n'
        '  web: {impostor: false, lods: [0.5]}\n'
        '  desktop:\n',
      );
      // What an older build without classes wrote.
      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: DeviceClass.values,
      );
      File('$generated/sphere.f3d').writeAsBytesSync(<int>[0]);

      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: deviceClassesForTargetOS(null),
      );
      final left = <String>[
        for (final entity in Directory(generated).listSync())
          if (entity.path.endsWith('.f3d'))
            entity.path.substring(generated.length + 1),
      ];
      expect(left, <String>['sphere.web.f3d']);

      // And a native build after it writes the other two back.
      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: deviceClassesForTargetOS(OS.android),
      );
      expect(File('$generated/sphere.phone.f3d').existsSync(), isTrue);
      expect(File('$generated/sphere.desktop.f3d').existsSync(), isTrue);
      expect(File('$generated/sphere.web.f3d').existsSync(), isFalse);
    });

    test('a class the build carries but the manifest leaves out reads the '
        'single .f3d, which is written for it', () async {
      // Mutation: drop the single target when classes are named, and the
      // desktop build below ships no file its desktop could read.
      manifest('classes:\n  phone: {impostor: false, lods: [0.5]}\n');
      List<String> left() => <String>[
        for (final entity in Directory(generated).listSync())
          if (entity.path.endsWith('.f3d'))
            entity.path.substring(generated.length + 1),
      ]..sort();

      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: deviceClassesForTargetOS(OS.macOS),
      );
      expect(left(), <String>['sphere.f3d', 'sphere.phone.f3d']);

      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: deviceClassesForTargetOS(null),
      );
      expect(left(), <String>['sphere.f3d']);

      // Every class the build carries named: the single file goes.
      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: <DeviceClass>[DeviceClass.phone],
      );
      expect(left(), <String>['sphere.phone.f3d']);
    });

    test('a project that asks for no classes gets exactly the single .f3d, '
        'and the cache entry it always had', () async {
      await runAssetBuild(
        project,
        log: _quiet(),
        deviceClasses: <DeviceClass>[DeviceClass.web],
      );
      final written = <String>[
        for (final entity in Directory(generated).listSync())
          if (entity.path.endsWith('.f3d'))
            entity.path.substring(generated.length + 1),
      ];
      expect(written, <String>['sphere.f3d']);
      final cache =
          jsonDecode(
                File('$generated/.flutter3d_cache.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(cache.keys, <String>['${project.path}/assets_src/sphere.obj']);
      expect((cache.values.single! as Map)['lods'], '');
      expect(_measure('$generated/sphere.f3d').sides, <int>[64]);
    });
  }, timeout: _slow);

  test('convert --classes writes one file per class, and a class that names '
      'no chain takes the command line\'s', () async {
    final scratch = Directory.systemTemp.createTempSync('f3d_convert_classes_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    _writeTexturedSphere(scratch);
    final err = StringBuffer();
    // The desktop alone: the phone's and the web's presets bake an impostor,
    // which the software rasteriser takes minutes over at their cell sizes.
    final code = await runConvert(
      <String>[
        '${scratch.path}/sphere.obj',
        '--textures',
        'none',
        '--lods',
        '0.5',
        '--classes',
        'desktop',
      ],
      out: _quiet(),
      err: _quiet(err),
    );
    expect(code, 0, reason: '$err');
    expect(File('${scratch.path}/sphere.f3d').existsSync(), isFalse);
    final desktop = _measure('${scratch.path}/sphere.desktop.f3d');
    expect(desktop.levels, 1);
    expect(desktop.sides, <int>[64]);
    expect(ConvertOptions.parse(<String>['a.obj', '--classes', 'tv']), isNull);
    expect(
      ConvertOptions.parse(<String>[
        'a.obj',
        '--classes',
        'web,phone',
      ])!.classes,
      <DeviceClass>[DeviceClass.web, DeviceClass.phone],
    );
  }, timeout: _slow);

  test('fitDocumentTextures clamps axis by axis and leaves the rest', () {
    final wide = img.encodePng(img.Image(width: 64, height: 8));
    final small = img.encodePng(img.Image(width: 8, height: 8));
    final document = PlainModelDocument(
      images: <EncodedImage>[
        EncodedImage(bytes: wide, name: 'wide'),
        EncodedImage(bytes: small, name: 'small'),
      ],
    );
    final fitted = fitDocumentTextures(document, 16);
    final first = img.decodeImage(fitted.images.first.bytes)!;
    expect((first.width, first.height), (16, 8));
    expect(fitted.images.last, same(document.images.last));
    expect(fitDocumentTextures(document, 64), same(document));
  });
}
