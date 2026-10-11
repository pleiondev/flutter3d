/// A render material names the physical one it is made of by id, and the
/// version of its program it was written for; a `.f3d` carries both, and
/// the physical materials of its own, in sections a 0.8 reader skips.
///
///     dart test test/formats/physical_materials_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show RenderMaterial;
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

/// A plugin's material in the envelope `flutter3d_matter` writes; this
/// package carries it without reading it.
const Map<String, Object?> _foam = <String, Object?>{
  'format': 'f3d.physicalMaterial',
  'version': 2,
  'id': 'acme.foam',
  'name': 'Packing foam',
  'phase': 'solid',
  'mechanical': <String, Object?>{'density': 30.0, 'source': 'a datasheet'},
};

F3dDocument _box() =>
    F3dDocument.parse(File('test/fixtures/v1/box.f3d').readAsBytesSync());

/// The box with [materials] in place of its own.
PlainModelDocument _with(List<SurfaceMaterial> materials) {
  final box = _box();
  return PlainModelDocument(
    surfaces: box.surfaces,
    materials: materials,
    images: box.images,
    nodes: box.nodes,
  );
}

/// Every section kind in [bytes]'s directory, as a 0.8 reader walks it.
Set<int> _kinds(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final entryBytes = view.getUint32(4, Endian.little) == 1
      ? f3dSectionEntryBytes
      : view.getUint32(12, Endian.little);
  return <int>{
    for (var i = 0; i < view.getUint32(8, Endian.little); i++)
      view.getUint32(f3dHeaderBytes + i * entryBytes, Endian.little),
  };
}

void main() {
  test('the sections take the numbers after the bundle\'s', () {
    // Fixed for good once a file is written with them. Mutation: renumber
    // either and every file written since reads as something else.
    expect(F3dSection.physicalMaterials, 36);
    expect(F3dSection.materialReferences, 37);
    expect(F3dSection.known, containsAll(<int>[36, 37]));
  });

  test('a material keeps its physical id and its version through a .f3d', () {
    final bytes = F3dWriter(
      _with(<SurfaceMaterial>[
        SurfaceMaterial(
          name: 'glass',
          physicalMaterial: 'f3d.glass',
          materialVersion: 3,
        ),
        SurfaceMaterial(name: 'plain'),
        SurfaceMaterial(name: 'foam', physicalMaterial: 'acme.foam'),
      ]),
      physicalMaterials: <String, Map<String, Object?>>{'acme.foam': _foam},
    ).write();
    final back = F3dDocument.parse(bytes);

    // Mutation: drop the references section from the writer, or read it at
    // the wrong offset, and the ids and the version are gone.
    expect(back.materials[0].physicalMaterial, 'f3d.glass');
    expect(back.materials[0].materialVersion, 3);
    expect(back.materials[1].physicalMaterial, isNull);
    expect(back.materials[1].materialVersion, isNull);
    expect(back.materials[2].physicalMaterial, 'acme.foam');
    expect(back.materials[2].materialVersion, isNull);
    expect(back.physicalMaterials, <String, Map<String, Object?>>{
      'acme.foam': _foam,
    });
  });

  test('a file that says nothing of either writes neither section', () {
    final bytes = F3dWriter(_box()).write();

    // So a model without them is the bytes it always was. Mutation: write
    // the sections even when empty and this names them.
    expect(_kinds(bytes), isNot(contains(F3dSection.physicalMaterials)));
    expect(_kinds(bytes), isNot(contains(F3dSection.materialReferences)));
  });

  test('both sections leave a file a 0.8 reader opens', () {
    final bytes = F3dWriter(
      _with(<SurfaceMaterial>[
        SurfaceMaterial(physicalMaterial: 'acme.foam', materialVersion: 2),
      ]),
      physicalMaterials: <String, Map<String, Object?>>{'acme.foam': _foam},
    ).write();

    // Version 1 and neither section flagged: the 0.8.5 loader skips kinds
    // it does not know. Mutation: flag either as must-understand and the
    // file becomes version 2, which a 0.8 game refuses.
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 1);
    expect(
      _kinds(bytes),
      containsAll(<int>[
        F3dSection.physicalMaterials,
        F3dSection.materialReferences,
      ]),
    );
  });

  test('a physical material that is not keyed by its own id is refused', () {
    // Mutation: write whatever key was given, and a level asking for
    // `acme.foam` finds a document that says it is something else.
    expect(
      () => F3dWriter(
        _box(),
        physicalMaterials: <String, Map<String, Object?>>{'acme.sponge': _foam},
      ),
      throwsArgumentError,
    );
  });

  test('re-exporting a bundle keeps its physical materials', () {
    final bytes = F3dWriter(
      _box(),
      physicalMaterials: <String, Map<String, Object?>>{'acme.foam': _foam},
    ).write();
    final again = F3dWriter.carrying(F3dDocument.parse(bytes)).write();

    // Mutation: leave `physicalMaterials` out of `F3dWriter.carrying` and
    // the second file has none.
    expect(F3dDocument.parse(again).physicalMaterials.keys, <String>[
      'acme.foam',
    ]);
  });

  test('the version 2 fixture opens with its physical materials', () {
    final bundle = F3dDocument.parse(
      File('test/fixtures/v2/physical.f3d').readAsBytesSync(),
    );

    // Minted once from `v2/bundle.f3d` with a material bound to the
    // catalog's glass at version 3 and a plugin's foam carried whole.
    // Mutation: read either section at another offset and this fails.
    expect(bundle.version, 2);
    expect(bundle.materials.single.physicalMaterial, 'f3d.glass');
    expect(bundle.materials.single.materialVersion, 3);
    expect(bundle.physicalMaterials['acme.foam']?['id'], 'acme.foam');
    expect(bundle.programs['RimGlow'], contains('material RimGlow'));
    expect(bundle.triangleCount, 12);
  });

  test('a .fmat names its physical material and keeps a whole version', () {
    final document = MaterialDocument(
      surface: SurfaceMaterial(physicalMaterial: 'f3d.oak', materialVersion: 4),
    );
    final text = writeFmat(document);
    final back = readFmat(Uint8List.fromList(utf8.encode(text)));

    // Mutation: let the float writer turn the version into 4.0, or forget
    // either key in the reader, and this fails; an unknown key would also
    // warn.
    expect(text, contains('"materialVersion": 4,'));
    expect(text, contains('"physicalMaterial": "f3d.oak"'));
    expect(back.surface.physicalMaterial, 'f3d.oak');
    expect(back.surface.materialVersion, 4);
    expect(back.warnings, isEmpty);
  });

  test('a render material names what it is made of, and a copy keeps it', () {
    final material = RenderMaterial(physicalMaterial: 'f3d.oak');

    // Mutation: leave the field out of `copy()` and the copy is made of
    // nothing named, the way `depthWrite` was once lost.
    expect(material.copy().physicalMaterial, 'f3d.oak');
    expect(RenderMaterial().physicalMaterial, isNull);
  });
}
