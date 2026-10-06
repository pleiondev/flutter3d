/// `P12`: what `ext.flutter3d.render.*` answers, asked of captures built by
/// hand — no VM, no window, no GPU.
///
///     flutter test test/render_inspection_test.dart
///
/// The extensions are a transport; the decisions are here. What an unknown
/// pass is told, what a pixel past the edge is told, how a NaN crosses JSON,
/// and — the one that matters most — that a float target this backend could
/// not read as floats is reported unread rather than clean.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A 2×2 RGBA8 image whose pixel at (x, y) has red `10 * (y * 2 + x)`.
CapturedImage _bytes(String resource) => CapturedImage(
  resource: resource,
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
  pixels: ByteData.sublistView(
    Uint8List.fromList(<int>[
      0, 1, 2, 255, //
      10, 11, 12, 255,
      20, 21, 22, 255,
      30, 31, 32, 255,
    ]),
  ),
);

/// A 2×2 half-float target with floats beside its bytes, one of them [bad].
CapturedImage _hdr({double bad = 0.5, bool floats = true}) => CapturedImage(
  resource: 'hdr colour',
  width: 2,
  height: 2,
  format: TextureFormat.r16g16b16a16Float,
  pixels: ByteData(16),
  floats: floats
      ? Float32List.fromList(<double>[
          0.1, 0.2, 0.3, 1.0, //
          0.1, 0.2, 0.3, 1.0,
          0.1, bad, 0.3, 1.0,
          0.1, 0.2, 0.3, 1.0,
        ])
      : null,
);

FrameCapture _frame({CapturedImage? hdr}) => FrameCapture(
  width: 2,
  height: 2,
  passes: <CapturedPass>[
    CapturedPass(
      name: 'scene',
      active: true,
      reads: const <String>[],
      optionalReads: const <String>[],
      writes: const <String>['hdr colour'],
      keeps: const <String>[],
      images: <CapturedImage>[hdr ?? _hdr()],
      micros: 400,
      drawCalls: 2,
      triangles: 24,
    ),
    CapturedPass(
      name: 'composite',
      active: true,
      reads: const <String>['hdr colour'],
      optionalReads: const <String>[],
      writes: const <String>['frame'],
      keeps: const <String>[],
      images: <CapturedImage>[_bytes('frame')],
      micros: 100,
      drawCalls: 1,
      triangles: 1,
    ),
  ],
  draws: <DrawRecord>[
    for (final (i, name) in <String>['crate', 'barrel'].indexed)
      DrawRecord(
        index: i,
        passIndex: 0,
        pass: 'scene',
        kind: 'mesh',
        mesh: name,
        material: 'wood',
        lighting: 'pbr',
        vertices: 24,
        indices: 36,
        instances: 1,
        triangles: 12,
        state: const <String, Object?>{'cull': 'back'},
        uniforms: <String, List<double>>{
          'tint': <double>[1.0, double.nan, 1.0, 1.0],
        },
      ),
  ],
  undetailedDraws: const <String, int>{'composite': 1},
);

void main() {
  group('passes', () {
    test('lists each pass with its inputs, outputs, size and format', () {
      final answer = renderPasses(_frame());
      final passes = answer['passes']! as List<Map<String, Object?>>;

      expect(passes.map((p) => p['name']), <String>['scene', 'composite']);
      expect(passes[1]['index'], 1);
      expect(passes[1]['reads'], <String>['hdr colour']);
      final output = (passes[0]['outputs']! as List).single as Map;
      expect(output['format'], 'r16g16b16a16Float');
      expect(output['width'], 2);
      expect(output['floats'], isTrue);
    });
  });

  group('a pass is named by index or by name', () {
    test('and an unknown name is refused with the names there are', () {
      // Mutation: answering an empty map for a name nobody has hands the
      // caller "nothing wrong" about a pass that does not exist.
      final answer = renderPassOutput(_frame(), <String, String>{
        'pass': 'bloom',
      });
      expect(isRefusal(answer), isTrue);
      expect(answer['refused'], contains('scene, composite'));
    });

    test('and an index past the end says how many passes ran', () {
      final answer = renderReadPixel(_frame(), <String, String>{
        'pass': '7',
        'x': '0',
        'y': '0',
      });
      expect(answer['refused'], contains('numbered 0 to 1'));
    });

    test('and an output the pass did not write is refused by name', () {
      final answer = renderPassOutput(_frame(), <String, String>{
        'pass': 'composite',
        'resource': 'depth',
      });
      expect(answer['refused'], contains('it wrote frame'));
    });
  });

  group('passOutput', () {
    test('is a PNG of the pass output', () {
      final answer = renderPassOutput(_frame(), <String, String>{'pass': '1'});
      final png = base64Decode(answer['png']! as String);
      expect(png.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      expect(answer['resource'], 'frame');
    });

    test('of an unreadable output passes on why', () {
      final frame = _frame(
        hdr: const CapturedImage(
          resource: 'hdr colour',
          width: 2,
          height: 2,
          format: TextureFormat.r16g16b16a16Float,
          refused: 'tile memory: there is nothing to read',
        ),
      );
      final answer = renderPassOutput(frame, <String, String>{'pass': '0'});
      expect(answer['refused'], contains('tile memory'));
    });
  });

  group('readPixel', () {
    test('answers the byte at x, y and not its neighbour', () {
      // Mutation: `(x * width + y)` reads (0, 1) as (1, 0) — 10 instead of 20.
      final answer = renderReadPixel(_frame(), <String, String>{
        'pass': 'composite',
        'x': '0',
        'y': '1',
      });
      expect(answer['uint'], <int>[20, 21, 22, 255]);
      expect(answer['float'], isNull);
      expect(answer['floatUnread'], contains('holds no floats'));
    });

    test('answers the float where the backend kept one', () {
      final answer = renderReadPixel(_frame(), <String, String>{
        'pass': 'scene',
        'x': '1',
        'y': '0',
      });
      expect(answer['float'], <Object>[
        closeTo(0.1, 1e-6),
        closeTo(0.2, 1e-6),
        closeTo(0.3, 1e-6),
        1.0,
      ]);
    });

    test('refuses a pixel past the edge, naming the size', () {
      // Mutation: checking only `x + y * width < pixels` lets (2, 0) through
      // as the first pixel of the next row — a real answer about the wrong
      // place.
      final answer = renderReadPixel(_frame(), <String, String>{
        'pass': 'composite',
        'x': '2',
        'y': '0',
      });
      expect(answer['refused'], contains('2x2'));
      expect(
        renderReadPixel(_frame(), <String, String>{
          'pass': 'composite',
          'x': '0',
          'y': '-1',
        }),
        contains('refused'),
      );
    });

    test('carries a NaN as a string JSON can hold', () {
      final answer = renderReadPixel(
        _frame(hdr: _hdr(bad: double.nan)),
        <String, String>{'pass': 'scene', 'x': '0', 'y': '1'},
      );
      expect((answer['float']! as List)[1], 'NaN');
      expect(() => jsonEncode(answer), returnsNormally);
    });
  });

  group('scanNan', () {
    test('finds a NaN and names the pass, the count and where', () {
      final answer = renderScanNan(
        _frame(hdr: _hdr(bad: double.nan)),
        const <String, String>{},
      );
      expect(answer['clean'], isFalse);
      final found = (answer['found']! as List).single as Map;
      expect(found['pass'], 'scene');
      expect(found['nan'], 1);
      expect(found['infinite'], 0);
      expect((found['first']! as List).single, <String, Object?>{
        'x': 0,
        'y': 1,
        'channel': 1,
        'value': 'NaN',
      });
      expect(() => jsonEncode(answer), returnsNormally);
    });

    test('counts an infinity apart from a NaN', () {
      final answer = renderScanNan(
        _frame(hdr: _hdr(bad: double.negativeInfinity)),
        const <String, String>{},
      );
      final found = (answer['found']! as List).single as Map;
      expect(found['nan'], 0);
      expect(found['infinite'], 1);
    });

    test('a clean frame is clean, and its eight-bit output is counted', () {
      final answer = renderScanNan(_frame(), const <String, String>{});
      expect(answer['clean'], isTrue);
      expect(answer['scanned'], 1);
      expect(answer['eightBit'], 1);
      expect(answer['unread'], isEmpty);
    });

    test('a float target read back as bytes is unread, not clean', () {
      // **The whole reason this is not a loop over `pixels`.** A NaN clamps
      // to an ordinary byte on every hardware backend's readback, so a scan
      // of the bytes finds nothing and says so. Mutation: treating an image
      // with no floats as scanned reports this frame clean.
      final answer = renderScanNan(
        _frame(hdr: _hdr(floats: false)),
        const <String, String>{},
      );
      expect(answer['scanned'], 0);
      final unread = (answer['unread']! as List).single as Map;
      expect(unread['resource'], 'hdr colour');
      expect(unread['why'], contains('eight bits'));
    });

    test('an unknown pass is refused', () {
      final answer = renderScanNan(_frame(), <String, String>{'pass': 'sky'});
      expect(answer['refused'], contains('no pass is called "sky"'));
    });
  });

  group('draws', () {
    test('lists every described draw and what each pass only counted', () {
      final answer = renderDraws(_frame(), const <String, String>{});
      expect(answer['total'], 2);
      expect(
        (answer['draws']! as List).map((d) => (d as Map)['mesh']),
        <String>['crate', 'barrel'],
      );
      expect(answer['undetailed'], <String, int>{'composite': 1});
    });

    test('pages, and filters by pass', () {
      final page = renderDraws(_frame(), <String, String>{
        'offset': '1',
        'limit': '1',
      });
      expect((page['draws']! as List).single, containsPair('mesh', 'barrel'));
      final composite = renderDraws(_frame(), <String, String>{
        'pass': 'composite',
      });
      expect(composite['total'], 0);
      expect(composite['undetailed'], <String, int>{'composite': 1});
    });

    test('a capture taken without the journal says so', () {
      final frame = FrameCapture(width: 2, height: 2, passes: _frame().passes);
      expect(
        renderDraws(frame, const <String, String>{})['refused'],
        contains('without the draw journal'),
      );
    });
  });

  group('draw', () {
    test('answers one draw with its state and uniforms, JSON-safe', () {
      final answer = renderDraw(_frame(), <String, String>{'index': '1'});
      expect(answer['mesh'], 'barrel');
      expect(answer['state'], <String, Object?>{'cull': 'back'});
      expect((answer['uniforms']! as Map)['tint'], <Object>[
        1.0,
        'NaN',
        1.0,
        1.0,
      ]);
      expect(() => jsonEncode(answer), returnsNormally);
    });

    test('an index past the end says how many there are', () {
      final answer = renderDraw(_frame(), <String, String>{'index': '2'});
      expect(answer['refused'], contains('numbered 0 to 1'));
    });
  });

  group('stats', () {
    test('sums the passes and sizes each target by its format', () {
      final answer = renderStats(_frame());
      expect(answer['passes'], 2);
      expect(answer['drawCalls'], 3);
      expect(answer['triangles'], 25);
      expect(answer['cpuMicros'], 500);
      // 2×2 at eight bytes, and 2×2 at four.
      expect(answer['targetBytes'], 2 * 2 * 8 + 2 * 2 * 4);
    });
  });

  test('a real software frame answers every question end to end', () async {
    // The capture the extensions take, on the one backend that keeps floats:
    // a lit cube scans clean and its scene pass reads back as floats.
    const size = 16;
    final device = CpuDevice(
      width: size,
      height: size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(1.4)).build(),
          ),
          Material(name: 'crate'),
          name: 'crate',
        ),
      )
      ..add(LightNode(intensity: 6.0)..setPosition(2.0, 3.0, 4.0))
      ..add(
        CameraNode()
          ..setPosition(0.0, 0.0, 4.0)
          ..lookAt(Vector3.zero()),
      );
    final renderer = Renderer.create(device: device);
    final pending = renderer.captureNextFrame(
      draws: true,
      readFloats: device.readHdrPixels,
    );
    renderer.render(
      width: size,
      height: size,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
    );
    final capture = await pending;

    final scan = renderScanNan(capture, const <String, String>{});
    expect(scan['clean'], isTrue);
    expect(scan['scanned'], greaterThan(0));
    expect(
      renderDraws(capture, const <String, String>{})['draws'],
      contains(containsPair('mesh', 'crate')),
    );
    final pixel = renderReadPixel(capture, <String, String>{
      'pass': 'scene',
      'x': '8',
      'y': '8',
    });
    expect(pixel['float'], hasLength(4));
    expect(() => jsonEncode(renderPasses(capture)), returnsNormally);
    expect(() => jsonEncode(renderStats(capture)), returnsNormally);
  });

  test('pick: the draws of the node under the pixel, of that frame alone', () {
    // Two crates of one name, which is what a level gives a row of them:
    // the picked one's draws are its own, not its namesake's.
    // Mutation: matching by name, which answers both.
    final device = CpuDevice(
      width: 2,
      height: 2,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final box = SharedMeshes(device).box(Vector3.all(1.0));
    final picked = MeshNode(box, Material(), name: 'crate');
    final namesake = MeshNode(box, Material(), name: 'crate');
    DrawRecord draw(int index, MeshNode node) => DrawRecord(
      index: index,
      passIndex: 0,
      pass: 'scene',
      kind: 'mesh',
      mesh: node.name,
      material: 'wood',
      lighting: 'pbr',
      vertices: 24,
      indices: 36,
      instances: 1,
      triangles: 12,
      state: const <String, Object?>{},
      uniforms: const <String, List<double>>{},
      node: node,
    );
    final capture = FrameCapture(
      width: 2,
      height: 2,
      passes: const <CapturedPass>[],
      draws: <DrawRecord>[draw(0, namesake), draw(1, picked), draw(2, picked)],
    );
    final answer = renderPicked(capture, picked, x: 1, y: 0);
    expect(answer['node'], 'crate');
    expect(answer['draws'], <int>[1, 2]);
    expect(
      renderPicked(capture, null, x: 1, y: 0)['says'],
      contains('clear colour'),
    );
  });
}
