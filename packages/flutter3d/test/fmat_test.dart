/// A material as a file: read, written back, and read by somebody else's reader.
///
///     flutter test test/fmat_test.dart
///
/// **Why a material wants to be a file at all.** A look is authored once and
/// worn by many meshes, and glTF cannot say that — it writes the material into
/// every file that uses it, so changing the studio's brushed steel means
/// re-exporting every model made of it. Nothing here uploads anything: reading a
/// material is pure, which is what lets all of this run with no GPU and no
/// Flutter binding doing any work.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String source) => Uint8List.fromList(utf8.encode(source));

/// A material as somebody would write it by hand.
const String _steel = '''
{
  "fmat": 1,
  "name": "brushed-steel",
  "lighting": "pbr",
  "baseColor": [0.6, 0.62, 0.65, 1.0],
  "metallic": 1.0,
  "roughness": 0.35,
  "textures": {
    "albedo": "steel.png",
    "normal": {"path": "steel_n.png", "wrapS": "clampToEdge", "mipmaps": false}
  }
}
''';

void main() {
  group('a hand-written material', () {
    test('reads as the factors and slots it names', () {
      final document = readFmat(_bytes(_steel));
      final surface = document.surface;

      expect(surface.name, 'brushed-steel');
      expect(surface.metallic, 1.0);
      expect(surface.roughness, 0.35);
      expect(surface.baseColor.r, closeTo(0.6, 1e-6));
      expect(document.lighting, same(LightingModel.pbr));

      final normal = surface.normalTexture!;
      expect(document.images[normal.imageIndex], 'steel_n.png');
      expect(normal.sampling.wrapS, TextureWrap.clampToEdge);
      expect(
        normal.sampling.useMipmaps,
        isFalse,
        reason: 'a slot that asks for no chain must not get one',
      );
    });

    test('and turns its paths into indices, interning repeats', () {
      // **The rule `TextureBinding` states, applied here.** Always an index,
      // never a path — so a consumer uploads images without knowing which format
      // they came from. One image used by two slots must therefore be one entry,
      // or the uploader decodes the same PNG twice and holds it twice.
      //
      // Mutation: append to `images` without interning — the two indices differ
      // and `images` has two entries; both halves of this fail.
      final document = readFmat(
        _bytes('''
        {"fmat": 1, "textures":
          {"albedo": "atlas.png", "occlusion": "atlas.png"}}
      '''),
      );

      expect(document.images, <String>['atlas.png']);
      expect(
        document.surface.baseColorTexture!.imageIndex,
        document.surface.occlusionTexture!.imageIndex,
      );
    });

    test('and keeps a slot the engine has no field for', () {
      // A custom shader's own sampler — foam, a flow map, a mask. The engine has
      // five named slots and an application's shader may declare more; dropping
      // what it does not recognise would make `.fmat` useless for exactly the
      // materials it exists to carry.
      //
      // Mutation: drop the `extraTextures` entry — fails here.
      final document = readFmat(
        _bytes(
          '{"fmat": 1, "textures": {"albedo": "a.png", "flow": "flow.png"}}',
        ),
      );

      expect(document.extraTextures.keys, <String>['flow']);
      expect(
        document.images[document.extraTextures['flow']!.imageIndex],
        'flow.png',
      );
      expect(
        document.surface.baseColorTexture,
        isNotNull,
        reason: 'the named slots must still be named slots',
      );
    });
  });

  group('a shader of the application\'s own', () {
    test('is named with what it binds, not just with what it is called', () {
      // **The contract the engine cannot reflect.** A compiled shader reports a
      // uniform block as present because the GLSL declared it, even when it
      // binds no buffer for it — and binding that phantom block segfaults inside
      // Metal with no Dart stack trace. So a file naming a shader the engine
      // does not ship must also say what that shader reads.
      //
      // Mutation: default `environment` to true — the renderer binds a cube to
      // a shader with no slot for it, which is the crash this shape prevents.
      final document = readFmat(
        _bytes('''
        {"fmat": 1, "lighting":
          {"shader": "Water", "label": "Sea water",
           "environment": true, "metallicRoughnessMap": false}}
      '''),
      );

      final lighting = document.lighting!;
      expect(lighting.shaderName, 'Water');
      expect(lighting.label, 'Sea water');
      expect(lighting.usesEnvironment, isTrue);
      expect(lighting.usesMetallicRoughnessMap, isFalse);
      expect(lighting.usesFragInfo, isTrue, reason: 'defaults still apply');
    });

    test('and what it does not claim, it does not get', () {
      // **The defaults have to fall the safe way, and only this says so.** The
      // test above sets the flags, so it would pass whichever way they defaulted
      // — and the dangerous direction is the permissive one: an environment cube
      // bound to a shader with no slot for it is a native crash, not a warning.
      // A file that names a shader and says nothing else is asking for the
      // ordinary lit contract, which is the one every backend's bundle has.
      //
      // Mutation: default `environment` or `metallic` to true — fails here.
      final lighting = readFmat(
        _bytes('{"fmat": 1, "lighting": {"shader": "Water"}}'),
      ).lighting!;

      expect(lighting.usesEnvironment, isFalse);
      expect(lighting.usesMetallic, isFalse);
      expect(lighting.label, 'Water', reason: 'the name doubles as the label');
    });

    test('and its parameters arrive as the floats a block wants', () {
      // Mutation: read a single number as an empty list — the shader gets a
      // block of zeroes and the material looks wrong rather than failing.
      final document = readFmat(
        _bytes('''
        {"fmat": 1, "parameterBlock": "WaterParams",
         "parameters": {"tint": [0.1, 0.4, 0.5], "speed": 2.5}}
      '''),
      );

      expect(document.parameterBlock, 'WaterParams');
      // Compared loosely on purpose. A parameter block is float32 on the GPU, so
      // 0.1 authored in JSON is 0.10000000149011612 by the time it is a
      // parameter — and a reader that kept it exact would be storing a number
      // the shader cannot receive.
      expect(document.parameters['tint']!, <Matcher>[
        closeTo(0.1, 1e-7),
        closeTo(0.4, 1e-7),
        closeTo(0.5, 1e-7),
      ]);
      // A single number is one float, not nothing: a shader asking for a scalar
      // would otherwise get a block of zeroes and merely look wrong.
      expect(document.parameters['speed'], <double>[2.5]);
    });

    test('and a shader nobody ships is a warning, not a crash', () {
      // Naming `"lighting": "Water"` as a bare string cannot work — the engine
      // has no way to know what that shader binds — but the material's colours
      // are still good, and a level should not fail to load over it.
      //
      // Mutation: throw instead of warning — fails here.
      final document = readFmat(
        _bytes('{"fmat": 1, "lighting": "Water", "metallic": 1.0}'),
      );

      expect(document.lighting, isNull);
      expect(document.surface.metallic, 1.0);
      expect(document.warnings.single, contains('Water'));
      expect(
        document.warnings.single,
        contains('object'),
        reason: 'the warning should say what to do instead',
      );
    });
  });

  group('what a material editor stands on', () {
    test('is that writing and reading back gives the same material', () {
      // Mutation: omit `roughness` from `writeFmat` when it is not the default —
      // it comes back as 0.5 and this fails. The same holds for every field
      // written conditionally, which is why this compares the whole thing.
      final original = readFmat(_bytes(_steel));
      final again = readFmat(_bytes(writeFmat(original)));

      expect(_shapeOf(again), _shapeOf(original));
      expect(again.images, original.images);
      expect(again.lighting, same(LightingModel.pbr));
      // And the reader knows every key the writer emits. `readFmat` warns on
      // an unknown top-level key, so a key added to `writeFmat` and not to
      // its `knownKeys` set warns on the writer's own output — which is only
      // caught if somebody looks. Mutation: emit `'extra': 1` from
      // `writeFmat` — this reports false while nothing else moves.
      expect(
        again.warnings,
        isEmpty,
        reason:
            'the writer wrote a key the '
            'reader does not know; add it to readFmat\'s knownKeys',
      );
    });

    test('and that a custom shader survives the trip too', () {
      final original = readFmat(
        _bytes('''
        {"fmat": 1, "name": "sea", "lighting":
          {"shader": "Water", "environment": true, "materialParameters": false},
         "parameters": {"speed": [2.5]},
         "textures": {"flow": {"path": "flow.png", "mipmaps": false}}}
      '''),
      );
      final again = readFmat(_bytes(writeFmat(original)));

      expect(again.lighting!.shaderName, 'Water');
      expect(again.lighting!.usesEnvironment, isTrue);
      expect(again.lighting!.usesMaterialParameters, isFalse);
      expect(again.parameters['speed'], <double>[2.5]);
      expect(again.extraTextures['flow']!.sampling.useMipmaps, isFalse);
      expect(
        again.warnings,
        isEmpty,
        reason:
            'the same, for the keys only a '
            'custom shader makes the writer emit',
      );
    });

    test('and that an unusual sampler is written long and a plain one short', () {
      // Not a formatting preference: a file an artist edits by hand should show,
      // in a diff, that only the path changed. Mutation: always write the object
      // form — the second half fails.
      final written = writeFmat(readFmat(_bytes(_steel)));

      expect(written, contains('"albedo": "steel.png"'));
      expect(written, contains('"clampToEdge"'));
    });
  });

  group('a hint beside a parameter', () {
    test('describes the control each kind wants, and nothing else', () {
      // **Description, never constraint.** `speed` is hinted `0..10` and the
      // file says 25; the reader must hand the shader 25, because a range that
      // clamped would change what the engine draws in order to tidy up an
      // editor's slider — and every golden in this repository was rendered with
      // the numbers the files actually carry.
      //
      // Mutation: clamp a parameter to its hinted range in `readFmat` — the
      // last expectation here fails, and it is the only one that would.
      final document = readFmat(
        _bytes('''
        {"fmat": 1,
         "parameters": {"speed": 25.0},
         "hints": {
           "speed": {"kind": "range", "min": 0, "max": 10, "step": 0.5,
                     "label": "Current", "help": "Metres a second."},
           "tint": {"kind": "color", "channels": 3},
           "foam": {"kind": "texture", "extensions": [".png"]},
           "mood": {"kind": "enum",
                    "values": ["calm", {"value": "storm", "label": "Storm"}]}
         }}
      '''),
      );

      final speed = document.hints['speed']!;
      expect(speed.label, 'Current');
      expect(speed.help, 'Metres a second.');
      expect((speed.kind as RangeHint).min, 0.0);
      expect((speed.kind as RangeHint).max, 10.0);
      expect((speed.kind as RangeHint).step, 0.5);
      expect((document.hints['tint']!.kind as ColorHint).channels, 3);
      expect((document.hints['foam']!.kind as TextureHint).extensions, <String>[
        '.png',
      ]);
      final mood = document.hints['mood']!.kind as EnumHint;
      expect(mood.values.map((v) => v.value), <String>['calm', 'storm']);
      expect(
        mood.values.map((v) => v.label),
        <String>['calm', 'Storm'],
        reason: 'a choice given no label is its own label',
      );
      expect(document.warnings, isEmpty);
      expect(
        document.parameters['speed'],
        <double>[25.0],
        reason: 'a hint described the control and moved the value',
      );
    });

    test('and survives being written back out', () {
      // The property a material inspector stands on, for hints as for factors:
      // an editor that reads a file and saves it must not lose what it did not
      // show. Mutation: drop `hints` from `writeFmat` — the shape differs and
      // this fails; drop `'hints'` from `readFmat`'s `knownKeys` and the writer
      // warns on its own output, which the round trip above already catches.
      final original = readFmat(
        _bytes('''
        {"fmat": 1, "parameters": {"speed": [2.5], "tint": [1, 0, 0]},
         "hints": {
           "speed": {"kind": "range", "min": 0, "max": 4, "help": "How fast."},
           "tint": {"kind": "color", "channels": 3},
           "mood": {"kind": "enum", "values": [{"value": "s", "label": "Storm"}]}
         }}
      '''),
      );
      final again = readFmat(_bytes(writeFmat(original)));

      expect(_hintsOf(again), _hintsOf(original));
      expect(again.warnings, isEmpty);
    });

    test('and a kind nobody defined is a warning, not a refusal', () {
      // The same answer `alphaMode` gives a word it does not know, and for a
      // stronger reason: a hint that will not parse costs a slider, and a
      // material that will not load costs the level. A tool three versions
      // ahead may write a curve here.
      //
      // Mutation: throw on an unknown kind — the material stops loading over a
      // decoration, and both halves of this fail.
      final document = readFmat(
        _bytes(
          '{"fmat": 1, "parameters": {"curve": [1, 2]}, '
          '"hints": {"curve": {"kind": "spline"}}}',
        ),
      );

      expect(document.hints, isEmpty);
      expect(document.parameters['curve'], <double>[1.0, 2.0]);
      expect(document.warnings.single, contains('spline'));
      expect(document.warnings.single, contains('curve'));
    });

    test('and the fields the engine already knows are hinted by the engine', () {
      // **Not written into every file, and that is the whole decision.**
      // Roughness runs nought to one in every material ever authored; a file
      // carrying that sentence would put a hundred identical lines in front of
      // the six an artist edits, and the readable diff is why this format is
      // text at all. So the built-in fields are hinted here and a file hints
      // only what this table cannot know.
      //
      // Mutation: drop `SurfaceAlphaMode.blend` from the alpha list, or a model
      // from `LightingModel.builtIn`'s use here — the two exhaustiveness
      // expectations fail.
      expect((builtInMaterialHints['roughness']!.kind as RangeHint).max, 1.0);
      expect((builtInMaterialHints['metallic']!.kind as RangeHint).min, 0.0);
      expect(
        (builtInMaterialHints['normalScale']!.kind as RangeHint).max,
        1.0,
      );
      expect(
        (builtInMaterialHints['occlusionStrength']!.kind as RangeHint).max,
        1.0,
      );
      expect((builtInMaterialHints['baseColor']!.kind as ColorHint).channels, 4);
      expect(
        (builtInMaterialHints['emissive']!.kind as ColorHint).channels,
        3,
        reason: 'a surface does not glow transparently',
      );
      expect(
        (builtInMaterialHints['alphaMode']!.kind as EnumHint).values.map(
          (v) => v.value,
        ),
        SurfaceAlphaMode.values.map((mode) => mode.name),
      );
      expect(
        (builtInMaterialHints['lighting']!.kind as EnumHint).values.map(
          (v) => v.value,
        ),
        LightingModel.builtIn.map((model) => model.shaderName),
        reason: 'the picker offers the shaders the engine ships',
      );
    });
  });

  group('a file this engine will not guess at', () {
    test('is one from a newer version', () {
      // **Deliberately not read as best-effort.** The difference between the two
      // versions is precisely what would be silently dropped, and a material
      // that loads looking wrong is worse than one that says why.
      //
      // Mutation: read it anyway — fails here.
      expect(
        () => readFmat(_bytes('{"fmat": 99, "metallic": 1.0}')),
        throwsA(isA<FormatException>()),
      );
    });

    test('and one that never said it was a material', () {
      expect(
        () => readFmat(_bytes('{"metallic": 1.0}')),
        throwsA(isA<FormatException>()),
      );
      expect(
        isFmat(_bytes('{"metallic": 1.0}')),
        isFalse,
        reason: 'somebody else\'s JSON is not ours to claim',
      );
      expect(isFmat(_bytes(_steel)), isTrue);
    });

    test('and an alpha mode nobody defined is a warning and opaque', () {
      // Mutation: throw on it — a typo in one key would cost the level.
      final document = readFmat(_bytes('{"fmat": 1, "alphaMode": "dissolve"}'));

      expect(document.surface.alphaMode, SurfaceAlphaMode.opaque);
      expect(document.warnings.single, contains('dissolve'));
    });

    // The failure the doc comment claims to prevent, and the one a text
    // format exists to make survivable: a hand-edit with a letter too many
    // used to load with the default roughness and say nothing at all.
    // Mutation: dropping `roughnesss` from the misspelling below — or
    // dropping the `knownKeys` filter from `readFmat` — leaves `warnings`
    // empty and the single-warning expectation reports false.
    test('and a misspelt key is named rather than silently dropped', () {
      final document = readFmat(
        _bytes('{"fmat": 1, "roughnesss": 0.9, "roughness": 0.2}'),
      );

      expect(document.surface.roughness, 0.2);
      expect(document.warnings.single, contains('roughnesss'));
    });

    // The open half of the format, which must stay quiet: an extra texture
    // slot and an extra parameter are how a custom shader asks for something
    // this engine has never heard of. Mutation: dropping `'textures'` from
    // `readFmat`'s `knownKeys` warns about the very namespace that is open on
    // purpose, and the empty-warnings expectation reports false.
    test('and an extra texture slot or parameter is not a warning', () {
      final document = readFmat(
        _bytes(
          '{"fmat": 1, "textures": {"detail": "d.png"}, '
          '"parameters": {"windStrength": 2.0}}',
        ),
      );

      expect(document.extraTextures.keys, <String>['detail']);
      expect(document.parameters.keys, <String>['windStrength']);
      expect(document.warnings, isEmpty);
    });
  });
}

/// Everything a round trip has to preserve, as one comparable value.
///
/// A string rather than field-by-field expectations, because the point is that
/// *nothing* was dropped: a test naming the fields it checks is a test that goes
/// quiet the day somebody adds a sixth.
String _shapeOf(MaterialDocument document) {
  final s = document.surface;
  String v(Object? value) => value.toString();
  String slot(TextureBinding? binding) => binding == null
      ? '-'
      : '${document.images[binding.imageIndex]}'
            '/${binding.sampling.wrapS.name}/${binding.sampling.useMipmaps}';

  return <String>[
    v(s.name),
    v(s.baseColor),
    v(s.metallic),
    v(s.roughness),
    v(s.normalScale),
    v(s.occlusionStrength),
    v(s.emissive),
    v(s.emissiveStrength),
    s.alphaMode.name,
    v(s.alphaCutoff),
    v(s.doubleSided),
    v(s.unlit),
    slot(s.baseColorTexture),
    slot(s.normalTexture),
    slot(s.metallicRoughnessTexture),
    slot(s.occlusionTexture),
    slot(s.emissiveTexture),
    document.parameterBlock,
    for (final entry in document.parameters.entries)
      '${entry.key}=${entry.value.toList()}',
    for (final entry in document.extraTextures.entries)
      '${entry.key}=${slot(entry.value)}',
  ].join('|');
}

/// Every hint as one comparable value, for the same reason [_shapeOf] is one:
/// a round-trip test that names the kinds it checks goes quiet the day a fifth
/// kind arrives.
String _hintsOf(MaterialDocument document) => <String>[
  for (final entry in document.hints.entries)
    <String>[
      entry.key,
      '${entry.value.label}',
      '${entry.value.help}',
      switch (entry.value.kind) {
        RangeHint(:final min, :final max, :final step) =>
          'range $min..$max by $step',
        ColorHint(:final channels) => 'color x$channels',
        TextureHint(:final extensions) => 'texture ${extensions.join(',')}',
        EnumHint(:final values) =>
          'enum ${values.map((v) => '${v.value}=${v.label}').join(',')}',
      },
    ].join(':'),
].join('|');
