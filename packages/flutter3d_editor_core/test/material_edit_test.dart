/// [materialWith]'s own gate, moved here from `flutter3d_editor`'s material
/// panel (mat-03) once `MaterialDocument` left `flutter3d` for
/// `flutter3d_formats`.
///
///     dart test test/material_edit_test.dart
///
/// `readFmat` almost never refuses anything — an alpha mode it has never heard
/// of becomes opaque with a note — so a caller writing straight into a material
/// document would be the one place that can produce a file which does not say
/// what it appears to say. What these tests assert is that the gate this file
/// exists for actually stands: a value that fits is accepted, one that does not
/// is refused, and refusing never touches the document handed in.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:test/test.dart';

/// A material file with one of everything a gate has to reason about: a
/// colour, a range, a finite set, a texture slot, and a parameter only the
/// file itself can describe.
const String _fmat = '''
{
  "fmat": 1,
  "name": "brick",
  "baseColor": [0.6, 0.3, 0.2, 1.0],
  "roughness": 0.8,
  "alphaMode": "blend",
  "textures": { "albedo": "brick.png" },
  "parameters": { "windStrength": [0.3] },
  "hints": {
    "windStrength": {
      "kind": "range", "min": 0.0, "max": 2.0, "step": 0.1, "label": "Wind"
    }
  }
}
''';

MaterialDocument _document() =>
    readFmat(Uint8List.fromList(utf8.encode(_fmat)));

void main() {
  test('a material file takes a value outside the hint it carries', () {
    // **The decision the engine already made, kept.** A hint describes a
    // control and never constrains the reader: 1.5 is what the shader
    // receives, and an editor that refused to write it could not save a file
    // it can draw.
    //
    // Mutation: clamp to the hint's ends in the gate. This fails, and a caller
    // becomes unable to represent a file the engine reads happily.
    final next = materialWith(
      _document(),
      'roughness',
      1.5,
      hint: builtInMaterialHints['roughness'],
    );

    expect(next?.surface.roughness, 1.5);
  });

  test('and refuses a value its reader would only warn about', () {
    // **The gate this file exists for.** `readFmat` almost never refuses
    // anything — an alpha mode it has never heard of becomes opaque with a
    // note — so writing straight into a material document would be the one
    // place that can produce a file which does not say what it appears to
    // say.
    //
    // Mutation: return the document without comparing the warnings. The write
    // is accepted, the file says `"wobbly"`, and every reader of it silently
    // draws an opaque surface.
    expect(
      materialWith(
        _document(),
        'alphaMode',
        'wobbly',
        hint: builtInMaterialHints['alphaMode'],
      ),
      isNull,
    );
  });

  test('and refuses a value its reader would silently swallow', () {
    // The other half of the same hole: `_number` in the material reader
    // answers the default for a string and says nothing at all, where the
    // level reader throws. The hint is what makes this answerable — a range
    // takes a number.
    //
    // Mutation: drop the shape check. The write is accepted, the roughness the
    // artist set to 0.8 becomes the default, and nothing anywhere says so.
    expect(
      materialWith(
        _document(),
        'roughness',
        'very',
        hint: builtInMaterialHints['roughness'],
      ),
      isNull,
    );
  });

  test('and refuses a document its reader could not open at all', () {
    // A version this build does not read is the one thing `readFmat` does
    // refuse, and nothing built on this gate must be the thing that writes
    // one.
    expect(materialWith(_document(), 'fmat', 2), isNull);
  });

  test('and accepts a value that is already the reader default', () {
    // The writer omits a value equal to its default, so the key comes back
    // absent — which is the file being right without it, not the reader
    // having misunderstood. A gate that could not tell those apart would
    // refuse every field somebody set back to its default.
    final next = materialWith(
      _document(),
      'roughness',
      0.5,
      hint: builtInMaterialHints['roughness'],
    );

    expect(next?.surface.roughness, 0.5);
  });

  test('and an accepted write keeps everything the file was carrying', () {
    // The gate goes through the writer and the reader, so anything either of
    // them dropped would be dropped by editing one field. The hints are the
    // part worth pinning: they are what the next caller's panel is built
    // from.
    final next = materialWith(
      _document(),
      'roughness',
      0.25,
      hint: builtInMaterialHints['roughness'],
    )!;

    expect(next.hints['windStrength'], isA<MaterialHint>());
    expect((next.hints['windStrength']!.kind as RangeHint).max, 2.0);
    expect(next.parameters['windStrength']!.first, closeTo(0.3, 1e-6));
    expect(writeFmat(next).contains('brick.png'), isTrue);
  });
}
