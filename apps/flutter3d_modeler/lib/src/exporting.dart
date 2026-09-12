/// Taking the document out to a format somebody else reads.
///
/// **An export is allowed to lose what the target cannot hold; a save is not.**
/// That is the whole difference between this file and `writeProject`. A project
/// file keeps the parameters a cylinder still knows itself by, the hierarchy and
/// the history; an OBJ keeps triangles and a colour, and a glTF keeps most of
/// the rest. So this asks `ExportReadiness` first and puts what will be lost in
/// front of the person, rather than deciding for them.
///
/// **Nothing here writes a file.** It builds bytes and hands back what to call
/// them, so a test can ask what an export of a project contains without a disk,
/// a picker or a sandbox — the same bargain `element_picking.dart` struck for
/// clicks. The widget's half is one `saveAs` per file.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What the model can be taken out as.
///
/// Three, and all of them are already written elsewhere. glTF joined this
/// enum with nothing else to change here, exactly as this doc comment once
/// predicted it would: the shape of the work is `document → writer →
/// bytes`, and the writer is the only part that differs.
enum ExportFormat {
  /// The engine's own container: every surface, material, image, node and
  /// animation this repository knows how to write.
  f3d('.f3d', 'the engine container'),

  /// Wavefront OBJ with its `.mtl` beside it. The oldest thing every tool
  /// reads, and the least it can carry: triangles, a placement baked into
  /// them, and a Phong approximation of each material.
  obj('.obj', 'triangles that every tool reads'),

  /// A self-contained glTF binary — `fmt-06`'s own `GltfWriter`, the format
  /// most of the rest of the world actually opens. Everything OBJ cannot
  /// carry survives this one: the node tree, materials with textures,
  /// skins and animation.
  glb('.glb', 'a glTF binary most other tools open');

  const ExportFormat(this.suffix, this.says);

  final String suffix;

  /// One line for a menu, in the words a person recognises.
  final String says;
}

/// One file an export produced.
final class ExportFile {
  const ExportFile(this.name, this.bytes);

  /// The name to offer the save panel, suffix and all.
  final String name;

  final Uint8List bytes;

  @override
  String toString() => 'ExportFile($name, ${bytes.length} bytes)';
}

/// What asking to export gave back.
///
/// **Three cases rather than bytes-or-null**, because the third one is the
/// point. A project that will not export cleanly is neither a success nor a
/// failure: it is a question for the person, and the compiler asking about all
/// three is what stops a caller writing a file that quietly lost an object.
sealed class ExportResult {
  const ExportResult();
}

/// The bytes, and what was lost on the way.
final class ExportWritten extends ExportResult {
  const ExportWritten(this.files, this.warnings);

  /// One for `.f3d`, two for OBJ — the `.obj` and its `.mtl`. In the order they
  /// should be written, the file that names the other first.
  final List<ExportFile> files;

  /// What the target could not hold, in sentences. Empty is the ordinary case.
  final List<String> warnings;
}

/// Nothing to write, and why.
final class ExportRefused extends ExportResult {
  const ExportRefused(this.because);

  final String because;

  @override
  String toString() => 'ExportRefused($because)';
}

/// It would write, and something in it will not load.
///
/// The caller shows [issues] and asks; `planExport(force: true)` writes anyway.
/// A refusal that could not be overridden would be this file deciding what
/// somebody's model is for.
final class ExportBlocked extends ExportResult {
  const ExportBlocked(this.issues);

  /// The errors from `ExportReadiness`, worst first. Warnings are not here —
  /// they ride along with [ExportWritten] and stop nothing.
  final List<ExportIssue> issues;

  /// The question, in one line.
  String get says =>
      '${issues.length == 1 ? 'One thing' : '${issues.length} things'} in this '
      'model will not load where it is going. Export anyway?';
}

/// [project] with every object's own node transform baked into its geometry,
/// where that is possible — `ui-17`'s own "bake node transforms" checkbox.
///
/// **Reuses `ApplyTransform` rather than a second transform-baking
/// implementation.** That command already does exactly this for one object
/// at a time — moves the vertices, flips normals on a mirroring determinant,
/// resets the node to identity — and a copy of it here would be a second
/// place that math could drift from the first. Called against a project a
/// caller is about to throw away for something exported instead, never
/// against the live, undoable one.
///
/// **Not every object can be baked, and this does not stop for the ones that
/// cannot.** `ApplyTransform` refuses a parametric shape, an imported mesh
/// and a socket — each for its own reason, all already explained on
/// `ApplyTransform` itself — and an object already at the identity leaves
/// nothing to bake. Every one of those keeps its own node transform exactly
/// as it was; only the objects `ApplyTransform` actually accepts end up with
/// an identity matrix on the other side.
ModelProject bakeAllTransforms(ModelProject project) {
  var next = project;
  for (final ModelObject object in project.objects) {
    final outcome = ApplyTransform(
      object.id,
    ).apply(next, ProjectSelection.none);
    if (outcome.ok) next = outcome.project!;
  }
  return next;
}

/// [project] as files, or the reason it is not.
///
/// [force] carries a person's answer to [ExportBlocked] back in. It skips the
/// error gate and nothing else: the warnings still come back with the bytes,
/// because "I know" is an answer to a question and not a reason to stop asking.
///
/// [bakeTransforms] runs [bakeAllTransforms] first, so the readiness check
/// and the writer both see the baked project — a transform that collapses a
/// shell of positive volume into one of zero should be caught before export,
/// not discovered by whoever opens the file next.
ExportResult planExport(
  ModelProject project, {
  required ExportFormat format,
  String name = 'model',
  bool force = false,
  bool bakeTransforms = false,
}) {
  if (bakeTransforms) project = bakeAllTransforms(project);
  // An empty project is refused rather than written, and this is the one place
  // that differs from `ObjWriter`, which writes an empty file on purpose and
  // says why. The difference is the caller: a format has to represent nothing,
  // and a person pressing Export on an empty document has made a mistake.
  if (project.objects.isEmpty) {
    return const ExportRefused('There is nothing in this project to export.');
  }

  // Triangles either way, because both writers write triangles: `ObjWriter`
  // bakes each surface's `MeshData`, which `toModelDocument` has already cut.
  // OBJ *the format* holds an n-gon and this writer does not, so warning about
  // quads is honest for both targets rather than a glTF rule leaking.
  final readiness = ExportReadiness.check(project);
  if (!force && !readiness.canExport) {
    return ExportBlocked(<ExportIssue>[
      for (final ExportIssue issue in readiness.issues)
        if (issue.severity == ExportSeverity.error) issue,
    ]);
  }

  final warnings = <String>[
    for (final ExportIssue issue in readiness.issues) issue.message,
  ];

  final ModelDocument document = toModelDocument(project);
  // The converter's own complaints — a parent that is not there, a transform
  // that is not a translate, rotate and scale. They belong beside readiness
  // rather than under it: readiness is about the model, these are about the
  // trip.
  warnings.addAll(document.warnings);

  switch (format) {
    case ExportFormat.f3d:
      return ExportWritten(<ExportFile>[
        ExportFile('$name.f3d', F3dWriter(document).write()),
      ], warnings);

    case ExportFormat.glb:
      return ExportWritten(<ExportFile>[
        ExportFile('$name.glb', GltfWriter(document).writeGlb()),
      ], warnings);

    case ExportFormat.obj:
      final writer = ObjWriter(document, name: name);
      final library = writer.writeMaterialLibrary();
      // Said once, here, rather than per object: OBJ has no node tree at all,
      // so a hierarchy does not survive it and every child comes back at the
      // place its parent put it. Somebody exporting a rig to OBJ should hear
      // that before they open it somewhere else and find it flat.
      const flattened =
          'OBJ has no node tree, so the hierarchy is baked into the vertices: '
          'the model looks right and comes back as one level of objects.';
      return ExportWritten(
        <ExportFile>[
          ExportFile('$name.obj', writer.write()),
          if (library != null) ExportFile(writer.materialLibraryName, library),
        ],
        <String>[
          ...warnings,
          if (project.objects.any((ModelObject o) => o.parent != null))
            flattened,
        ],
      );
  }
}
