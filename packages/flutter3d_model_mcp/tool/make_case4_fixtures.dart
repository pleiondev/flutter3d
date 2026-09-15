// Generates test/fixtures/tutorial/case4.* by running the scenario
// `case4_scenario.dart` describes, and renders the one real headless
// "expected result" frame the case's own page embeds under
// cloud/server/web/assets/learn/modeler/character-from-a-bare-mesh/, plus
// text-labelled placeholder PNGs for every screen this session cannot
// screenshot for real (see that file's own doc comment and the case page).
// Run once by hand after a deliberate change to the scenario or the writers
// it exercises; read the diff before committing the new fixtures.
//
//     dart run tool/make_case4_fixtures.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import '../test/fixtures/tutorial/case4_scenario.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<void> _renderTo(ModelProject project, String path) async {
  final png = await renderProject(
    RenderRequest(project: project, view: RenderProjectView.iso),
    deviceFactory: _cpuDevice,
  );
  File(path).writeAsBytesSync(png);
  stderr.writeln('wrote $path');
}

/// The same five-by-seven glyph table `make_case3_fixtures.dart` restates for
/// its own placeholders — see that file's own doc comment for why this is
/// copied a fourth time rather than shared.
const Map<String, List<String>> _font5x7 = <String, List<String>>{
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'E': ['#####', '#....', '#....', '###..', '#....', '#....', '#####'],
  'G': ['.###.', '#....', '#....', '#.###', '#...#', '#...#', '.###.'],
  'M': ['#...#', '##.##', '#.#.#', '#...#', '#...#', '#...#', '#...#'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'R': ['####.', '#...#', '#...#', '####.', '#..#.', '#...#', '#...#'],
  'S': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  'a': ['.....', '.....', '.###.', '....#', '.####', '#...#', '.####'],
  'c': ['.....', '.....', '.###.', '#....', '#....', '#....', '.###.'],
  'd': ['....#', '....#', '.####', '#...#', '#...#', '#...#', '.####'],
  'e': ['.....', '.....', '.###.', '#...#', '#####', '#....', '.###.'],
  'g': ['.....', '.....', '.####', '#...#', '#...#', '.####', '....#'],
  'h': ['#....', '#....', '#.###', '##..#', '#...#', '#...#', '#...#'],
  'i': ['..#..', '.....', '.##..', '..#..', '..#..', '..#..', '.###.'],
  'k': ['#....', '#....', '#..#.', '#.#..', '##...', '#.#..', '#..#.'],
  'l': ['.##..', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'm': ['.....', '.....', '##.##', '#.#.#', '#.#.#', '#.#.#', '#.#.#'],
  'n': ['.....', '.....', '#.##.', '##..#', '#...#', '#...#', '#...#'],
  'o': ['.....', '.....', '.###.', '#...#', '#...#', '#...#', '.###.'],
  'p': ['.....', '.....', '.###.', '#...#', '####.', '#....', '#....'],
  'r': ['.....', '.....', '#.##.', '##..#', '#....', '#....', '#....'],
  's': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
  't': ['..#..', '..#..', '####.', '..#..', '..#..', '..#..', '...#.'],
  'u': ['.....', '.....', '#...#', '#...#', '#...#', '#...#', '.####'],
  'v': ['.....', '.....', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'w': ['.....', '.....', '#...#', '#...#', '#.#.#', '#.#.#', '.#.#.'],
  'x': ['.....', '.....', '#...#', '.#.#.', '..#..', '.#.#.', '#...#'],
  'y': ['.....', '.....', '#...#', '#...#', '.####', '....#', '.###.'],
  'z': ['.....', '.....', '#####', '...#.', '..#..', '.#...', '#####'],
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

/// A screen this session cannot actually screenshot — matches case 1–3's own
/// placeholder convention exactly: a dark ground, [title] centred,
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
  final dir = Directory.systemTemp.createTempSync('make_case4_fixtures');
  final path = '${dir.path}/case4.f3dproj';

  final starting = await case4StartingProject();
  final session = ModelSession(ModelHistory(starting), path: path);
  await runCase4Scenario(session);

  final readiness = ExportReadiness.check(session.project);
  stderr.writeln('readiness: ${readiness.says}');

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final exported = session.export('${dir.path}/case4.glb');
  if (!exported.did) throw StateError('export refused: ${exported.says}');
  final journaled = session.journal('${dir.path}/case4.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case4.f3dproj', 'case4.glb', 'case4.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }

  final assetDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/character-from-a-bare-mesh',
  )..createSync(recursive: true);

  // The real render: the auto-rigged, weight-painted, morphed and posed
  // character exactly as `renderProject` draws it now — `tut-10`'s own fix
  // poses it through its own skeleton (the bend `PoseJoint` keyed, still the
  // project's own current joint transform) and blends the chest-puff shape
  // key at its own current weight, both read straight off `session.project`
  // rather than off any animation curve. See `doc/modeler-tutorial-gaps.md`.
  await _renderTo(
    session.project,
    '${assetDir.path}/07-character-real-geometry.png',
  );

  // The weight-paint gradient, real — `tut-11`'s own fix, over the same
  // left-elbow joint case 4's own second `PaintWeights` stroke touches.
  final skeleton = session.project.skeletons.single;
  final leftElbowId = skeleton.joints.firstWhere(
    (id) => session.project[id]!.name == 'leftElbow',
  );
  final gradientPng = await renderProject(
    RenderRequest(
      project: session.project,
      view: RenderProjectView.iso,
      shading: RenderShading.weights,
      weightsJoint: leftElbowId,
    ),
    deviceFactory: _cpuDevice,
  );
  File(
    '${assetDir.path}/02-weight-paint-gradient.png',
  ).writeAsBytesSync(gradientPng);
  stderr.writeln('wrote ${assetDir.path}/02-weight-paint-gradient.png');

  const placeholders = <String, String>{
    '01-autorig-dialog.png': 'Auto-rig',
    '03-bend-slider.png': 'Bend slider',
    '04-pose-and-keys.png': 'Pose and keys',
    '05-morphs-panel.png': 'Morphs panel',
    '06-game-preview.png': 'Game preview',
  };
  for (final entry in placeholders.entries) {
    File(
      '${assetDir.path}/${entry.key}',
    ).writeAsBytesSync(_placeholderPng(320, 180, entry.value));
    stderr.writeln('wrote ${assetDir.path}/${entry.key} (placeholder)');
  }

  dir.deleteSync(recursive: true);
}
