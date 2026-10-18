// A document names other files — a glTF its buffers and images, an OBJ its
// material library, a USD layer the layers it references and its textures —
// and the converter reads them. Every one of those has to lie inside the
// input's directory (for `convertFiles`, inside the upload): a document
// that climbs out with `..` or names an absolute path would otherwise put
// somebody's private file into the `.f3d` it hands back.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/convert.dart';
import 'package:flutter3d_build/src/convert.dart' show fileUriResolverFor;
import 'package:flutter3d_core/formats.dart' show AssetRequest;
import 'package:test/test.dart';

import 'convert_support.dart';

void main() {
  late Directory scratch;
  late Directory input;
  late String secret;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('f3d_confine_');
    input = Directory('${scratch.path}/in')..createSync();
    // What the payloads reach for: real files a reader would take, so a
    // converter that follows the reference converts them.
    final outside = Directory('${scratch.path}/private')..createSync();
    secret = outside.absolute.path;
    File('$secret/tri.bin').writeAsBytesSync(_triangleBuffer());
    File(
      '$secret/stolen.mtl',
    ).writeAsStringSync('newmtl Stolen\nKd 0.1 0.2 0.3\n');
    File(
      '$secret/id_rsa.png',
    ).writeAsBytesSync(File('$fixtures/wood.png').readAsBytesSync());
    File(
      '$secret/prop.usda',
    ).writeAsStringSync(File('$fixtures/usd/prop.usda').readAsStringSync());
    File(
      '$secret/hidden.gltf',
    ).writeAsStringSync(File('$fixtures/triangle.gltf').readAsStringSync());
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  /// [path] reached by climbing: far more `..` than there are directories,
  /// then down from the root to it.
  String climbing(String path) => '${'../' * 24}${path.substring(1)}';

  /// The three payloads of the review — a glTF buffer, an OBJ `mtllib`, a
  /// USD asset path — and the same reach from a Godot scene and a MaterialX
  /// image, each as the file it is written as.
  Map<String, String> payloads(
    String Function(String) refer,
  ) => <String, String>{
    'scene.tscn': _godotNaming(
      mesh: 'res://${refer('$secret/hidden.gltf')}',
      texture: 'res://${refer('$secret/id_rsa.png')}',
    ),
    'look.mtlx': File('$fixtures/materials.mtlx').readAsStringSync().replaceAll(
      'value="wood.png"',
      'value="${refer('$secret/id_rsa.png')}"',
    ),
    'tri.gltf': _gltfWithBuffer(refer('$secret/tri.bin')),
    'quad.obj': File('$fixtures/quad.obj').readAsStringSync().replaceFirst(
      'mtllib quad.mtl',
      'mtllib ${refer('$secret/stolen.mtl')}',
    ),
    'stage.usda': _usdaNaming(
      texture: refer('$secret/id_rsa.png'),
      layer: refer('$secret/prop.usda'),
    ),
  };

  group('the resolver', () {
    test('reads beside the model and below it, and refuses the rest', () async {
      // Mutation: open `File('$directory/$uri')` unchecked, as before; the
      // two refusals read the secret instead.
      File('${input.path}/sub/b.bin')
        ..parent.createSync()
        ..writeAsBytesSync(<int>[1, 2]);
      final resolve = fileUriResolverFor('${input.path}/a.gltf');
      Future<Uint8List> read(String uri) => resolve(AssetRequest(uri));
      expect(await read('sub/b.bin'), <int>[1, 2]);
      expect(await read('./sub/../sub/b.bin'), <int>[1, 2]);
      for (final uri in <String>[
        '../private/tri.bin',
        climbing('$secret/tri.bin'),
        '$secret/tri.bin',
        Uri.encodeComponent('../private/tri.bin'),
        r'sub\..\..\private\tri.bin',
      ]) {
        await expectLater(
          read(uri),
          throwsA(
            isA<SourceFormatException>().having(
              (SourceFormatException e) => e.message,
              'message',
              contains('outside'),
            ),
          ),
          reason: uri,
        );
      }
    });
  });

  group('flutter3d convert', () {
    for (final (label, refer) in <(String, String Function(String))>[
      ('climbing out with ..', climbing),
      ('by an absolute path', (String p) => p),
    ]) {
      test('no payload reaches a file $label', () async {
        // Mutation: drop the check in `fileUriResolverFor`, the USD layer's
        // `resolveFile`, Godot's `file` or MaterialX's `_image`: the
        // secret's buffer converts, `Stolen` becomes a material, `id_rsa.png`
        // a texture, and the private layer and glTF models of their own.
        for (final MapEntry(:key, :value) in payloads(refer).entries) {
          File('${input.path}/$key').writeAsStringSync(value);
          final out = Directory('${scratch.path}/out_$key')..createSync();
          final run = await convert(<String>[
            '${input.path}/$key',
          ], output: out);
          _expectNothingLeaked(out, run.report(key), key);
        }
      });
    }
  });

  group('convertFiles', () {
    test('a document in the upload reaches nothing outside it', () async {
      // Mutation: the code as it was, checking the keys and not the
      // references inside the documents — the climbing glTF converted the
      // private buffer, and the report said nothing.
      for (final MapEntry(:key, :value) in payloads(climbing).entries) {
        final result = await convertFiles(
          <String, Uint8List>{
            key: utf8.encode(value),
            'wood.png': File('$fixtures/wood.png').readAsBytesSync(),
          },
          to: ConversionTarget.everything,
          bundle: false,
        );
        final report = result.reports.single;
        for (final path in result.files.keys) {
          expect(path, isNot(contains('Stolen')), reason: key);
          expect(path, isNot(contains('id_rsa')), reason: key);
          expect(path, isNot(contains('models/prop')), reason: key);
          expect(path, isNot(contains('hidden')), reason: key);
        }
        _expectRefusalSaid(report.toJson(), key);
      }
    });

    test('a reference that stays inside the upload still resolves', () async {
      // Mutation: refuse every `..`, not only one that leaves the root, or
      // leave `ConvertContext.root` null in `convertFiles` so each layer is
      // held to its own directory: a layer one directory down naming
      // `../wood.png` loses its texture and its referenced prop.
      final result = await convertFiles(
        <String, Uint8List>{
          'scenes/stage.usda': utf8.encode(
            _usdaNaming(texture: '../wood.png', layer: '../prop.usda'),
          ),
          'prop.usda': File('$fixtures/usd/prop.usda').readAsBytesSync(),
          'wood.png': File('$fixtures/wood.png').readAsBytesSync(),
        },
        to: ConversionTarget.everything,
        entry: 'scenes/stage.usda',
        bundle: false,
      );
      expect(result.isOk, isTrue, reason: '${result.reports.single.toJson()}');
      expect(result.files.keys, contains('textures/wood.png'));
      expect(result.files.keys, contains('models/prop.f3d'));
    });
  });
}

/// The secret's bytes are in no file the run wrote, and the report says
/// why the reference was refused.
void _expectNothingLeaked(
  Directory out,
  Map<String, Object?> report,
  String input,
) {
  for (final file in out.listSync(recursive: true).whereType<File>()) {
    expect(file.path, isNot(contains('Stolen')), reason: input);
    expect(file.path, isNot(contains('id_rsa')), reason: input);
    expect(file.path, isNot(contains('models/prop')), reason: input);
    expect(file.path, isNot(contains('hidden')), reason: input);
    expect(
      latin1.decode(file.readAsBytesSync()),
      isNot(contains('Stolen')),
      reason: '$input: ${file.path}',
    );
  }
  _expectRefusalSaid(report, input);
}

void _expectRefusalSaid(Map<String, Object?> report, String input) {
  final said = <Object?>[
    report['error'],
    ...?report['dropped'] as List<Object?>?,
    ...?report['warnings'] as List<Object?>?,
  ].join('\n');
  expect(said, contains('outside'), reason: '$input: $report');
}

/// The fixture triangle's buffer, which it carries as a data URI.
Uint8List _triangleBuffer() {
  final gltf =
      jsonDecode(File('$fixtures/triangle.gltf').readAsStringSync())
          as Map<String, Object?>;
  final uri =
      ((gltf['buffers']! as List<Object?>).single!
              as Map<String, Object?>)['uri']!
          as String;
  return base64.decode(uri.substring(uri.indexOf(',') + 1));
}

/// The fixture triangle with its buffer read from [uri].
String _gltfWithBuffer(String uri) {
  final gltf =
      jsonDecode(File('$fixtures/triangle.gltf').readAsStringSync())
          as Map<String, Object?>;
  final buffer =
      (gltf['buffers']! as List<Object?>).single! as Map<String, Object?>;
  buffer['uri'] = uri;
  return jsonEncode(gltf);
}

/// A Godot scene drawing [mesh] in a material textured with [texture].
String _godotNaming({required String mesh, required String texture}) =>
    '''
[gd_scene load_steps=4 format=3]

[ext_resource type="ArrayMesh" path="$mesh" id="1_mesh"]
[ext_resource type="Texture2D" path="$texture" id="2_tex"]

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_leak"]
resource_name = "Leak"
albedo_texture = ExtResource("2_tex")

[node name="Root" type="Node3D"]

[node name="Body" type="MeshInstance3D" parent="."]
mesh = ExtResource("1_mesh")
surface_material_override/0 = SubResource("StandardMaterial3D_leak")
''';

/// A stage with a textured floor and a referenced layer.
String _usdaNaming({required String texture, required String layer}) =>
    '''
#usda 1.0
(
    defaultPrim = "World"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "World"
{
    def Mesh "Floor"
    {
        int[] faceVertexCounts = [4]
        int[] faceVertexIndices = [0, 1, 2, 3]
        point3f[] points = [(-1, 0, -1), (1, 0, -1), (1, 0, 1), (-1, 0, 1)]
        texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
            interpolation = "faceVarying"
        )
        rel material:binding = </World/Looks/Leak>
    }

    def Xform "Chair" (
        prepend references = @$layer@
    )
    {
    }

    def Scope "Looks"
    {
        def Material "Leak"
        {
            token outputs:surface.connect = </World/Looks/Leak/Surface.outputs:surface>

            def Shader "Surface"
            {
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor.connect = </World/Looks/Leak/Texture.outputs:rgb>
                token outputs:surface
            }

            def Shader "Texture"
            {
                uniform token info:id = "UsdUVTexture"
                asset inputs:file = @$texture@
                float3 outputs:rgb
            }
        }
    }
}
''';
