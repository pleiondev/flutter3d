/// `rel-13`: exporting the same document twice writes the same bytes.
///
///     dart test test/export_determinism_test.dart
///
/// **The property the row's own acceptance rests on and never states.** That
/// acceptance is `make_templates.py && git diff --exit-code` — regenerate
/// every template model and find no change — which says nothing at all unless
/// the writer is deterministic. If it is not, the check fails on the day
/// somebody runs it on a different machine and nobody learns anything about
/// the templates.
///
/// **What could make it non-deterministic, and is what this looks for.** A map
/// iterated in hash order; a `DateTime.now()` in a generator string; a
/// `Set` of materials walked in insertion order that depends on which object
/// was visited first; a float formatted by a locale. None of those shows up
/// in a round trip — the document reads back the same either way — and all of
/// them show up here, as two byte arrays that differ.
///
/// Every format, not only GLB, because the row names the export tool rather
/// than one writer and a build script is as likely to want an OBJ.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A document with more than one of everything a writer sorts: several
/// objects, several materials, a hierarchy, and an object whose transform is
/// not the identity.
ModelProject _sample() {
  var project = const ModelProject();
  for (final (String name, Vector3 at) in <(String, Vector3)>[
    ('crate', Vector3(0.0, 0.0, 0.0)),
    ('lamp', Vector3(1.5, 0.0, -2.0)),
    ('post', Vector3(-1.0, 0.5, 3.0)),
  ]) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: name,
        geometry: EditedGeometry(EditMesh.cuboid(size: Vector3(0.6, 0.9, 0.6))),
        transform: Matrix4.translation(at),
      ),
    );
  }

  final history = ModelHistory(project);
  for (final (String name, Vector4 colour) in <(String, Vector4)>[
    ('oak', Vector4(0.45, 0.30, 0.16, 1.0)),
    ('brass', Vector4(0.72, 0.58, 0.24, 1.0)),
    ('paint', Vector4(0.18, 0.34, 0.52, 1.0)),
  ]) {
    expect(history.run(AddMaterial(materialName: name)), isNull);
    expect(
      history.run(
        SetMaterialField(
          index: history.project.materials.length - 1,
          field: 'baseColor',
          value: <double>[colour.x, colour.y, colour.z, colour.w],
        ),
      ),
      isNull,
    );
  }
  return history.project;
}

/// [project] written as [format], or the sentence it refused with.
Uint8List _write(ModelProject project, ExportFormat format) {
  final ExportResult result = planExport(
    project,
    format: format,
    name: 'sample',
    force: true,
  );
  expect(
    result,
    isA<ExportWritten>(),
    reason: 'the fixture has to export before this can say anything',
  );
  final files = (result as ExportWritten).files;
  // Every file the export produced, in the order it produced them, joined:
  // an OBJ writes its `.mtl` beside it and a writer that ordered *those*
  // by a hash would be exactly the bug this looks for.
  final out = BytesBuilder(copy: false);
  for (final ExportFile file in files) {
    out
      ..add(file.name.codeUnits)
      ..add(file.bytes);
  }
  return out.toBytes();
}

void main() {
  group('the same document exports to the same bytes', () {
    for (final ExportFormat format in ExportFormat.values) {
      test('${format.name}, twice from one project', () {
        final project = _sample();
        expect(_write(project, format), _write(project, format));
      });

      test('${format.name}, from two documents built the same way', () {
        // Stronger than the pair above, and the one that catches identity
        // rather than content leaking into a file: two `ModelProject`s built
        // by the same steps are different objects with different hash codes,
        // so anything iterating a map or a set in hash order can come out in
        // a different order between them.
        expect(_write(_sample(), format), _write(_sample(), format));
      });
    }
  });

  test('a document that is not ready refuses rather than half-writing', () {
    // The other half of what a build script needs: a failure it can see. An
    // empty project has nothing to export, and the answer is a sentence.
    final ExportResult result = planExport(
      const ModelProject(),
      format: ExportFormat.glb,
      name: 'empty',
    );
    expect(result, isNot(isA<ExportWritten>()));
  });
}
