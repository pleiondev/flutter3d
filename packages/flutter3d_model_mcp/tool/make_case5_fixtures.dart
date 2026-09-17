// Generates test/fixtures/tutorial/case5.* by running the scenario
// `case5_scenario.dart` describes, and renders the one real headless
// "expected result" frame the case's own page embeds under
// cloud/server/web/assets/learn/modeler/borrowing-a-walk/, plus
// text-labelled placeholder PNGs for every screen this session cannot
// screenshot for real (see that file's own doc comment and the case page).
// Run once by hand after a deliberate change to the scenario or the writers
// it exercises; read the diff before committing the new fixtures.
//
//     dart run tool/make_case5_fixtures.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import '../test/fixtures/tutorial/case5_scenario.dart';

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

/// The same five-by-seven glyph table `make_case4_fixtures.dart` restates for
/// its own placeholders — see that file's own doc comment for why this is
/// copied a fifth time rather than shared.
const Map<String, List<String>> _font5x7 = <String, List<String>>{
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  'E': ['#####', '#....', '#....', '###..', '#....', '#....', '#####'],
  'G': ['.###.', '#....', '#....', '#.###', '#...#', '#...#', '.###.'],
  'M': ['#...#', '##.##', '#.#.#', '#...#', '#...#', '#...#', '#...#'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'R': ['####.', '#...#', '#...#', '####.', '#..#.', '#...#', '#...#'],
  'S': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  'a': ['.....', '.....', '.###.', '....#', '.####', '#...#', '.####'],
  'b': ['#....', '#....', '#.###', '##..#', '#...#', '#...#', '####.'],
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

/// A screen this session cannot actually screenshot — matches cases 1–4's
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
  final dir = Directory.systemTemp.createTempSync('make_case5_fixtures');
  final path = '${dir.path}/case5.f3dproj';

  final starting = await case5StartingProject();
  final session = ModelSession(ModelHistory(starting), path: path);
  await runCase5Scenario(session);

  final readiness = ExportReadiness.check(session.project);
  stderr.writeln('readiness: ${readiness.says}');

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final exported = session.export('${dir.path}/case5.glb');
  if (!exported.did) throw StateError('export refused: ${exported.says}');
  final journaled = session.journal('${dir.path}/case5.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case5.f3dproj', 'case5.glb', 'case5.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }

  final assetDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/borrowing-a-walk',
  )..createSync(recursive: true);

  // The one real render: case 4's own character, exactly as `renderProject`
  // draws it once the retargeted "animation 0" clip has landed and its root
  // motion has been extracted — real geometry, real materials, the real
  // 17-joint rig, both clips now on the project. `tut-10`
  // (`doc/modeler-tutorial-gaps.md`) already established that
  // `render_project.dart` never mentions "skin" or "skeleton" at all, so
  // this picture is the base mesh at its bind pose regardless of which of
  // the project's own two clips is "current" or what time within it — it
  // cannot be captioned as showing the walk cycle's own mid-clip pose, only
  // as the character the retarget actually landed on.
  await _renderTo(
    session.project,
    '${assetDir.path}/04-character-after-retarget.png',
  );

  const placeholders = <String, String>{
    '01-clip-library.png': 'Clip library',
    '02-bone-map-and-viewports.png': 'Bone map',
    '03-blend-slider.png': 'Blend slider',
  };
  for (final entry in placeholders.entries) {
    // Never over a picture that is already there — see
    // `make_case2_fixtures.dart`'s own note at the same spot.
    final file = File('${assetDir.path}/${entry.key}');
    if (file.existsSync()) {
      stderr.writeln('kept ${assetDir.path}/${entry.key} (already taken)');
      continue;
    }
    file.writeAsBytesSync(_placeholderPng(320, 180, entry.value));
    stderr.writeln('wrote ${assetDir.path}/${entry.key} (placeholder)');
  }

  dir.deleteSync(recursive: true);
}
