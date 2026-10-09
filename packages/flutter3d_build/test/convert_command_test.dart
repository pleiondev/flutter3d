import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:flutter3d_build/src/convert/command.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show DocumentFormatException;
import 'package:test/test.dart';

import 'convert_support.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_cmd_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  group('the command line', () {
    test('no input is a usage error, --help is not', () async {
      final err = BufferSink();
      expect(await runConvertCommand(const <String>[], err: err), 2);
      expect(err.text, contains('Usage: flutter3d convert'));
      final out = BufferSink();
      expect(await runConvertCommand(const <String>['--help'], out: out), 0);
      expect(out.text, contains('Exit codes'));
    });

    test('an unknown option is a usage error naming it', () async {
      final err = BufferSink();
      final code = await runConvertCommand(const <String>[
        'x.glb',
        '--frobnicate',
      ], err: err);
      expect(code, 2);
      expect(err.text, contains('--frobnicate'));
    });

    test('the model options parse as the model converter\'s do', () {
      final options = ConvertCommandSettings.parse(const <String>[
        'a.glb',
        '--lods=0.5,0.25',
        '--chunks',
        '--textures',
        'bc',
        '--no-mips',
      ])!;
      expect(options.models.lods, <double>[0.5, 0.25]);
      expect(options.models.chunks, isNotNull);
      expect(options.models.textures.name, 'bc');
      expect(options.models.mips, isFalse);
    });
  });

  group('inputs', () {
    test('a format is read from the extension, then from the bytes', () {
      expect(detectFormat('a.prefab')!.$1, 'unity-prefab');
      expect(detectFormat('a.tscn')!.$1, 'godot-scene');
      expect(detectFormat('a.usdz')!.$1, 'usd');
      expect(detectFormat('a.mtlx')!.$1, 'materialx');
      expect(detectFormat('a.glb')!.$1, 'gltf');
      final unnamed = File('${scratch.path}/layer')
        ..writeAsStringSync('#usda 1.0\n');
      expect(detectFormat(unnamed.path)!.$1, 'usd');
      final nothing = File('${scratch.path}/notes.txt')
        ..writeAsStringSync('hello');
      expect(detectFormat(nothing.path), isNull);
    });

    test('a glob expands sorted, a directory walks, a miss is a problem', () {
      final problems = <String>[];
      final found = expandInputs(<String>[
        '$fixtures/*.ply',
        '$fixtures/godot',
        '$fixtures/nothing*.obj',
      ], problems);
      expect(found.where((String p) => p.endsWith('.ply')).toList(), <String>[
        '$fixtures/cloud_points.ply',
        '$fixtures/quad_ascii.ply',
        '$fixtures/tri_binary.ply',
      ]);
      expect(found.any((String p) => p.endsWith('room.tscn')), isTrue);
      expect(found.any((String p) => p.endsWith('painted.tres')), isTrue);
      expect(found.any((String p) => p.endsWith('.obj')), isTrue);
      expect(problems.single, contains('matches nothing'));
    });

    test('the asset prefix is the relative output directory', () {
      expect(
        assetPrefixFor('assets_src/imported/', null),
        'assets_src/imported',
      );
      expect(assetPrefixFor('./out', null), 'out');
      expect(assetPrefixFor('/abs/out', null), '');
      expect(assetPrefixFor('/abs/out', 'assets/x'), 'assets/x');
    });
  });

  group('writing', () {
    test('a dry run writes nothing and says what it would', () async {
      final run = await convert(<String>[
        '$fixtures/quad.obj',
        '--dry-run',
      ], output: scratch);
      expect(run.code, 0);
      expect(run.json['dryRun'], isTrue);
      expect(scratch.listSync(), isEmpty);
      expect(run.report('quad.obj')['written'], contains('quad.f3d'));
    });

    test(
      'the same run twice writes the same bytes, and is no overwrite',
      () async {
        final first = await convert(<String>[
          '$fixtures/quad.obj',
        ], output: scratch);
        final bytes = File('${scratch.path}/quad.f3d').readAsBytesSync();
        final second = await convert(<String>[
          '$fixtures/quad.obj',
        ], output: scratch);
        expect(first.code, 0);
        expect(second.code, 0);
        expect(File('${scratch.path}/quad.f3d').readAsBytesSync(), bytes);
      },
    );

    test('a file with other contents is refused without --overwrite', () async {
      File('${scratch.path}/wedge.f3d').writeAsStringSync('mine');
      final refused = await convert(<String>[
        '$fixtures/wedge.stl',
      ], output: scratch);
      expect(refused.code, 4);
      expect(refused.report('wedge.stl')['outcome'], 'would-overwrite');
      expect(File('${scratch.path}/wedge.f3d').readAsStringSync(), 'mine');

      final replaced = await convert(<String>[
        '$fixtures/wedge.stl',
        '--overwrite',
      ], output: scratch);
      expect(replaced.code, 0);
      expect(
        File('${scratch.path}/wedge.f3d').readAsStringSync(),
        isNot('mine'),
      );
    });

    test('a failed input exits 1 and leaves the others written', () async {
      final run = await convert(<String>[
        '$fixtures/wedge.stl',
        '$fixtures/cloud_points.ply',
      ], output: scratch);
      expect(run.code, 1);
      expect(run.report('cloud_points.ply')['outcome'], 'failed');
      expect(run.report('cloud_points.ply')['error'], contains('point cloud'));
      expect(run.wrote('wedge.f3d'), isTrue);
    });

    test('--report writes the same report as JSON', () async {
      final path = '${scratch.path}/report.json';
      final code = await runConvertCommand(<String>[
        '$fixtures/wedge.stl',
        '-o',
        '${scratch.path}/out',
        '--report',
        path,
        '--split',
      ], out: BufferSink());
      expect(code, 0);
      // Mutation: write the bare list again and the envelope is gone.
      final document =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      expect(document['format'], 'f3d.convertReport');
      expect(document['version'], convertReportVersion);
      expect(convertReportsFrom(document).single['format'], 'stl');
    });

    test('the version 1 report and the bare list before it both read', () {
      // Minted on 2026-10-09 when `--report` went into the envelope.
      final fixture = jsonDecode(
        File('test/fixtures/v1/convert.report.json').readAsStringSync(),
      );
      final reports = convertReportsFrom(fixture);
      expect(reports.single['outcome'], 'converted');
      expect(
        convertReportsFrom((fixture as Map<String, Object?>)['reports']),
        reports,
      );
      expect(
        () => convertReportsFrom(<String, Object?>{...fixture, 'version': 2}),
        throwsA(isA<DocumentFormatException>()),
      );
    });
  });

  group('external tools', () {
    test('a tool is found on PATH, by its variable, or not at all', () {
      expect(
        fbx2gltf.locate(environment: const <String, String>{'PATH': ''}),
        isNull,
      );
      final fake = File('${scratch.path}/FBX2glTF')..writeAsStringSync('');
      expect(
        fbx2gltf.locate(environment: <String, String>{'PATH': scratch.path}),
        fake.path,
      );
      expect(
        fbx2gltf.locate(
          environment: <String, String>{
            'PATH': '',
            'FLUTTER3D_FBX2GLTF': fake.path,
          },
        ),
        fake.path,
      );
    });

    test('the exit codes order a failure before a missing tool before a '
        'refusal', () {
      expect(exitCodeFor(const <ConvertOutcome>[ConvertOutcome.converted]), 0);
      expect(
        exitCodeFor(const <ConvertOutcome>[
          ConvertOutcome.wouldOverwrite,
          ConvertOutcome.missingTool,
        ]),
        3,
      );
      expect(
        exitCodeFor(const <ConvertOutcome>[
          ConvertOutcome.missingTool,
          ConvertOutcome.failed,
        ]),
        1,
      );
    });

    test('an FBX with neither converter installed exits 3 and says how to '
        'get one', () async {
      if (fbx2gltf.locate() != null || blender.locate() != null) {
        markTestSkipped('a converter is installed on this machine');
        return;
      }
      final fbx = File('${scratch.path}/x.fbx')..writeAsStringSync('Kaydara');
      final run = await convert(<String>[
        fbx.path,
      ], output: Directory('${scratch.path}/o'));
      expect(run.code, 3);
      expect(run.report('x.fbx')['error'], contains('FBX2glTF'));
    });
  });
}
