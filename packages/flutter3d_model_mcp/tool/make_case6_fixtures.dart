// Generates test/fixtures/tutorial/case6.* by running the scenario
// `case6_scenario.dart` describes, and renders the one real headless
// "expected result" frame the case's own page embeds, plus one
// text-labelled placeholder PNG for the one screen this session cannot
// screenshot for real (see that file's own doc comment and the case page).
// Run once by hand after a deliberate change to the scenario or the writers
// it exercises; read the diff before committing the new fixtures.
//
//     dart run tool/make_case6_fixtures.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:vector_math/vector_math.dart';

import '../test/fixtures/tutorial/case1_scenario.dart';
import '../test/fixtures/tutorial/case6_scenario.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// [project]'s roots scaled up by [factor], for a render only — never for a
/// fixture a test reads back. Works around `tut-02` exactly the way
/// `make_case1_fixtures.dart`'s own `_scaledForRender` does, for the same
/// reason: case 6 starts from the identical millimetre-scale teapot case 1
/// imports, `render_project.dart`'s own `_frame` floors its fitted bounding
/// radius at `0.05` (5 cm), and an unscaled render of an 8 mm object asks the
/// camera to frame a handful of pixels in the middle of the picture.
ModelProject _scaledForRender(ModelProject project, double factor) {
  var scaled = project;
  final adjustment = Matrix4.diagonal3Values(factor, factor, factor);
  for (final object in project.objects.where((o) => o.parent == null)) {
    scaled = scaled.withObject(
      object.copyWith(transform: adjustment.multiplied(object.transform)),
    );
  }
  return scaled;
}

Future<void> _renderTo(ModelProject project, String path) async {
  final png = await renderProject(
    RenderRequest(
      project: _scaledForRender(project, 20),
      view: RenderProjectView.iso,
    ),
    deviceFactory: _cpuDevice,
  );
  File(path).writeAsBytesSync(png);
  stderr.writeln('wrote $path');
}

/// The same five-by-seven glyph table `make_case4_fixtures.dart`'s own doc
/// comment already explains copying rather than sharing — see that file for
/// why; this is the fifth copy in the tutorial fixture tools.
const Map<String, List<String>> _font5x7 = <String, List<String>>{
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'e': ['.....', '.....', '.###.', '#...#', '#####', '#....', '.###.'],
  'g': ['.....', '.....', '.####', '#...#', '#...#', '.####', '....#'],
  'n': ['.....', '.....', '#.##.', '##..#', '#...#', '#...#', '#...#'],
  't': ['..#..', '..#..', '####.', '..#..', '..#..', '..#..', '...#.'],
  's': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
  'i': ['..#..', '.....', '.##..', '..#..', '..#..', '..#..', '.###.'],
  'o': ['.....', '.....', '.###.', '#...#', '#...#', '#...#', '.###.'],
  'S': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
};

void _drawText(
  Uint8List rgb,
  int width,
  int height,
  String text,
  int x,
  int y,
  int scale,
  int color,
) {
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;
  var cx = x;
  for (final ch in text.split('')) {
    final glyph = _font5x7[ch] ?? _font5x7[' ']!;
    for (var row = 0; row < glyph.length; row++) {
      for (var col = 0; col < glyph[row].length; col++) {
        if (glyph[row][col] != '#') continue;
        for (var dy = 0; dy < scale; dy++) {
          final py = y + row * scale + dy;
          if (py < 0 || py >= height) continue;
          for (var dx = 0; dx < scale; dx++) {
            final px = cx + col * scale + dx;
            if (px < 0 || px >= width) continue;
            final o = (py * width + px) * 3;
            rgb[o] = r;
            rgb[o + 1] = g;
            rgb[o + 2] = b;
          }
        }
      }
    }
    cx += 6 * scale;
  }
}

int _textWidth(String text, int scale) => text.length * 6 * scale;

/// A screen this session cannot actually screenshot — matches cases 1-5's
/// own placeholder convention exactly: a dark ground, [title] centred,
/// "screenshot pending" centred below it in orange.
Uint8List _placeholderPng(int width, int height, String title) {
  const background = 0x2e3a46;
  const titleColor = 0xd8dee6;
  const captionColor = 0xd08a3e;
  const titleScale = 2;
  const captionScale = 2;
  const caption = 'screenshot pending';

  final bg = <int>[
    (background >> 16) & 0xFF,
    (background >> 8) & 0xFF,
    background & 0xFF,
  ];
  final rgb = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    rgb.setAll(i * 3, bg);
  }
  _drawText(
    rgb,
    width,
    height,
    title,
    ((width - _textWidth(title, titleScale)) ~/ 2).clamp(0, width),
    70,
    titleScale,
    titleColor,
  );
  _drawText(
    rgb,
    width,
    height,
    caption,
    (width - _textWidth(caption, captionScale)) ~/ 2,
    105,
    captionScale,
    captionColor,
  );

  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    raw.add(rgb.sublist(y * width * 3, (y + 1) * width * 3));
  }
  final idat = ZLibEncoder().convert(raw.toBytes());

  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    final crc = _crc32(<int>[...typeBytes, ...data]);
    out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type 2: truecolour, no alpha
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const <int>[]);
  return out.toBytes();
}

int _crc32(List<int> bytes) {
  const poly = 0xEDB88320;
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1 != 0) ? (crc >> 1) ^ poly : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('make_case6_fixtures');
  final path = '${dir.path}/case6.f3dproj';

  final imported = await case1ImportedProject();
  final session = ModelSession(ModelHistory(imported), path: path);
  await runCase6Scenario(session);

  final readiness = ExportReadiness.check(session.project);
  stderr.writeln('readiness: ${readiness.says}');

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final exported = session.export('${dir.path}/case6.glb');
  if (!exported.did) throw StateError('export refused: ${exported.says}');
  // Both the agent's own five tool calls and the person's own roughness
  // edit (straight through `session.history.run`, never through
  // `ModelSession.run`'s own tool surface) land here now — `ModelHistory
  // .run` itself records to the attached journal regardless of the door
  // a caller came in through (`tut-15`, closed).
  final journaled = session.journal('${dir.path}/case6.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case6.f3dproj', 'case6.glb', 'case6.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }

  final assetDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/an-agent-beside-you',
  )..createSync(recursive: true);

  // The one real render: this exact mixed-authorship project — case 1's
  // teapot, the agent's own baseColor/metallic, the person's own roughness
  // (0.35, not the agent's 0.28 from case 1) — through the same
  // `renderProject` every other case's own reference picture comes from.
  await _renderTo(session.project, '${assetDir.path}/02-final-material.png');

  // Screen 26 ("Сеанс агента" — tool-call feed, "You"/"Agent" history
  // badges, undo restricted to the agent's own steps, a six-view contact
  // sheet) has no app-side implementation in this build: only `mcp-16d`'s
  // seven `ui.*` tools and `--mcp-port` itself exist (`tut-16`,
  // `doc/modeler-tutorial-gaps.md`) — there is no live screen to point
  // `tool/tutorial/shoot.dart` at yet, real macOS run or not.
  File(
    '${assetDir.path}/01-agent-session-placeholder.png',
  ).writeAsBytesSync(_placeholderPng(320, 180, 'Agent session'));
  stderr.writeln(
    'wrote ${assetDir.path}/01-agent-session-placeholder.png (placeholder)',
  );

  dir.deleteSync(recursive: true);
}
