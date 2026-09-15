// Generates test/fixtures/tutorial/case2.* by running the scenario
// `case2_scenario.dart` describes, and renders the pictures the case's own
// page embeds under
// cloud/server/web/assets/learn/modeler/vase-from-a-profile/ — two real
// headless renders, plus four placeholder PNGs standing in for the running
// UI (see the doc comment on `_placeholderPng` for why those are
// generated here rather than shot for real). Run once by hand after a
// deliberate change to the scenario or the writers it exercises; read the
// diff before committing the new fixtures.
//
// `tut-22` (`doc/modeler-tutorial-gaps.md`): 05-vase-mesh.png and
// 06-vase-modifiers-preview.png were found to differ, deterministically,
// from a clean regenerate of the same HEAD — not because renderProject is
// nondeterministic (it isn't; see `render_project_test.dart`'s own
// `tut-22` group), but because `tut-07`'s own commit moved bloom's and
// shadows' defaults onto `SceneLighting`'s own (see
// `render_project.dart`'s doc comment) and this case never sets its own
// lighting at all, so both PNGs quietly went stale without anyone
// regenerating them. Regenerated deliberately as part of `tut-22`'s own fix.
//
//     dart run tool/make_case2_fixtures.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import '../test/fixtures/tutorial/case2_scenario.dart';

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

/// [project]'s object [id] with every one of its own modifier slots
/// switched off — the same thing `ToggleModifier` does to one slot at a
/// time, done to all of them at once, for a render only. Never applied to
/// the fixture that gets committed: the saved project keeps both
/// modifiers enabled, exactly as the scenario left them.
///
/// **Fixed by `tut-06`.** Before it, nothing between here and a drawn
/// frame read [ModelObject.modifiers] at all — not `SceneSync` in the live
/// app, not `renderProject` — so this file used to hand-evaluate the
/// stack itself (the same three lines [ApplyModifier.apply] runs) just to
/// give the case's own page one honest picture of the feature.
/// `renderProject` reads the stack live now, which is what makes the
/// *disabled* picture the one that needs a real recipe here: switching a
/// slot off is a real, live toggle a person can make from the modifier
/// panel, drawn through the exact same `renderProject` as the enabled
/// picture below it.
ModelProject _withModifiersDisabled(ModelProject project, int id) {
  final object = project[id]!;
  return project.withObject(
    object.copyWith(
      modifiers: <ModifierSlot>[
        for (final slot in object.modifiers) slot.copyWith(enabled: false),
      ],
    ),
  );
}

/// The five-by-seven glyphs [_placeholderPng] draws with — only the letters
/// this case's own four titles and its shared "screenshot pending" caption
/// actually use, not a general-purpose font.
const Map<String, List<String>> _font5x7 = <String, List<String>>{
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'M': ['#...#', '##.##', '#.#.#', '#...#', '#...#', '#...#', '#...#'],
  'a': ['.....', '.....', '.###.', '....#', '.####', '#...#', '.####'],
  'c': ['.....', '.....', '.###.', '#....', '#....', '#....', '.###.'],
  'd': ['....#', '....#', '.####', '#...#', '#...#', '#...#', '.####'],
  'e': ['.....', '.....', '.###.', '#...#', '#####', '#....', '.###.'],
  'f': ['..##.', '.#..#', '.#...', '###..', '.#...', '.#...', '.#...'],
  'g': ['.....', '.....', '.####', '#...#', '#...#', '.####', '....#'],
  'h': ['#....', '#....', '#.###', '##..#', '#...#', '#...#', '#...#'],
  'i': ['..#..', '.....', '.##..', '..#..', '..#..', '..#..', '.###.'],
  'k': ['#....', '#....', '#..#.', '#.#..', '##...', '#.#..', '#..#.'],
  'l': ['.##..', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'n': ['.....', '.....', '#.##.', '##..#', '#...#', '#...#', '#...#'],
  'o': ['.....', '.....', '.###.', '#...#', '#...#', '#...#', '.###.'],
  'p': ['.....', '.....', '.###.', '#...#', '####.', '#....', '#....'],
  'r': ['.....', '.....', '#.##.', '##..#', '#....', '#....', '#....'],
  's': ['.....', '.....', '.####', '#....', '.###.', '....#', '####.'],
  't': ['..#..', '..#..', '####.', '..#..', '..#..', '..#..', '...#.'],
};

/// [text] drawn into [rgb] (row-major, 3 bytes per pixel, [width] wide) at
/// [x],[y], each glyph pixel [scale] device pixels square, [color] as
/// `0xRRGGBB` — centred by the caller, which is why this returns nothing
/// and takes an already-placed `x` rather than centring itself.
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

/// A screen this session cannot actually screenshot — `apps/flutter3d_modeler`
/// needs a real macOS window (`flutter run -d macos`), which this
/// environment cannot open (see the case's own page and the commit message
/// for the full story). Matches case 1's own placeholder convention: a dark
/// ground, [title] centred, "screenshot pending" centred below it in
/// orange — rather than inventing a different look for this case's own four.
/// Built by hand — zlib-compressed scanlines through `dart:io`'s own
/// `ZLibEncoder`, a hand-rolled CRC32 — rather than left un-generated, so
/// `/learn/modeler/` still serves a real, decodable image at every path its
/// own Markdown names; `sips`/`file` both confirm what this writes decodes
/// as an ordinary 8-bit truecolour PNG.
Uint8List _placeholderPng(int width, int height, String title) {
  const background = 0x2e3a46;
  const titleColor = 0xd8dee6;
  const captionColor = 0xd08a3e;
  const titleScale = 3;
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
    (width - _textWidth(title, titleScale)) ~/ 2,
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
  final dir = Directory.systemTemp.createTempSync('make_case2_fixtures');
  final path = '${dir.path}/case2.f3dproj';

  final session = ModelSession(ModelHistory(const ModelProject()), path: path);
  runCase2Scenario(session);

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final journaled = session.journal('${dir.path}/case2.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case2.f3dproj', 'case2.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }

  final assetDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/vase-from-a-profile',
  )..createSync(recursive: true);

  // The vase mesh alone, mirror and array both switched off — a real,
  // live toggle (`_withModifiersDisabled`), not the saved project: the
  // committed fixture keeps both modifiers enabled.
  await _renderTo(
    _withModifiersDisabled(session.project, 1),
    '${assetDir.path}/05-vase-mesh.png',
  );

  // The saved project exactly as `renderProject` draws it today — mirror
  // and array both live, `tut-06`'s own fix. No hand evaluation: this is
  // the same render call as every other picture on this page.
  await _renderTo(
    session.project,
    '${assetDir.path}/06-vase-modifiers-preview.png',
  );

  const placeholders = <String, String>{
    '01-profile-editor.png': 'Profile editor',
    '02-mesh-edit-toolbar.png': 'Mesh edit tools',
    '03-modifier-stack.png': 'Modifier stack',
    '04-material-texture-panel.png': 'Material panel',
  };
  for (final entry in placeholders.entries) {
    File(
      '${assetDir.path}/${entry.key}',
    ).writeAsBytesSync(_placeholderPng(320, 180, entry.value));
    stderr.writeln('wrote ${assetDir.path}/${entry.key} (placeholder)');
  }

  dir.deleteSync(recursive: true);
}
