/// What a project refuses to export, and what it merely warns about.
///
/// **Two severities, and the line between them is whether the file opens.**
/// "How bad is it" is not a question anybody can answer on somebody else's
/// behalf, and a scale of five is a scale where every issue lands in the middle
/// of it. Whether the thing that comes out can be loaded at all does have one
/// answer, so that is where the line goes: an export panel greys its button out
/// on the errors and lists the warnings beside it, and both halves of that are
/// things a person can do something about.
///
/// **`MeshChecks` has a third level and this drops it on purpose.** A note — a
/// boundary edge, a quad — is worth knowing while modelling and is noise in
/// front of somebody who has already decided to export and wants to know what
/// will happen when they do. Sharing that enum would have saved a mapping and
/// cost the panel a level nobody can act on.
///
/// **Nothing here reimplements a check.** Surfaces meeting at a point, shells
/// wound inside out and faces with no area are `MeshChecks` in
/// `flutter3d_mesh`, which already walks the half-edges to find them. What is
/// here is what each of them means for an export, said about an object rather
/// than about a list of face ids — the panel that highlights the faces is the
/// modelling one, and the person about to press Export wants to know which of
/// their forty objects to open.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'project.dart';

/// Whether an issue stops the export or spoils the result.
enum ExportSeverity {
  /// It will load, and somebody will be disappointed by it: a model over
  /// budget, a shell inside out, a quad cut the way the exporter felt like.
  warning,

  /// It will not load, or it will load as nothing: an empty mesh, a face with
  /// no area.
  error,
}

/// One thing wrong with a project, before it leaves.
final class ExportIssue {
  const ExportIssue(this.severity, this.message, {this.object});

  final ExportSeverity severity;

  /// A sentence naming what is wrong and what to do, with the count in it.
  final String message;

  /// The object this is about, or null when it is the project as a whole.
  ///
  /// The budget is the case that has no object: it is spent by everything at
  /// once, and blaming the largest object for it would be blaming whichever
  /// one somebody happened to model first.
  final ModelObject? object;

  @override
  String toString() => '${severity.name}: $message';
}

/// Everything a project has to answer for before it can be written out.
final class ExportReadiness {
  const ExportReadiness._(this.issues);

  /// Measures [project] against its own profile.
  ///
  /// [trianglesOnly] says whether the target format can hold a face with more
  /// than three sides. glTF and GLB cannot, which is why it is the default and
  /// why every export this repository writes today wants it; OBJ can, and an
  /// export to one should pass false rather than be told off for a quad it is
  /// perfectly able to write. It is an argument rather than a field of
  /// `ProjectProfile` because the profile is about the machine that will draw
  /// the model and this is about the file on the way to it — `doc-13` puts a
  /// `requireTriangles` on the profile, and this moves there when it does.
  factory ExportReadiness.check(
    ModelProject project, {
    bool trianglesOnly = true,
  }) {
    final found = <ExportIssue>[
      // The budget goes first, ahead of the objects, because it is the one
      // fault that is true of all of them at once: a bar that led with a quad
      // in one object while the project as a whole was twelve times its budget
      // would be answering the smaller question. Warnings keep this order
      // through the two passes below, so the position is a choice rather than
      // an accident of where the call sits.
      ?_budget(project),
      for (final ModelObject object in project.objects)
        ..._issuesWith(object, trianglesOnly: trianglesOnly),
    ];
    // Worst first, by two passes rather than by a sort: `List.sort` is not
    // stable, so sorting on the severity alone would let two warnings swap
    // places between runs and a panel reorder itself while nothing changed.
    return ExportReadiness._(<ExportIssue>[
      for (final ExportIssue issue in found)
        if (issue.severity == ExportSeverity.error) issue,
      for (final ExportIssue issue in found)
        if (issue.severity == ExportSeverity.warning) issue,
    ]);
  }

  /// Errors first, then warnings, each in the order of the objects.
  final List<ExportIssue> issues;

  /// Whether anything here stops the file being written.
  bool get canExport =>
      issues.every((ExportIssue i) => i.severity != ExportSeverity.error);

  /// The worst of it, in one line, for a status bar.
  ///
  /// The count of the rest comes with it, because a bar that shows the first
  /// problem and hides that there are nine more is a bar that gets somebody to
  /// fix one thing and press Export again.
  String get says => switch (issues) {
    [] => 'ready to export',
    [final ExportIssue worst, ...final List<ExportIssue> rest] =>
      '${worst.severity == ExportSeverity.error ? 'will not export' : 'exports with a warning'}'
          ': ${worst.message}'
          '${rest.isEmpty ? '' : ' (and ${rest.length} more)'}',
  };

  @override
  String toString() => 'ExportReadiness(${issues.length} issues)';
}

/// The whole project against the profile's triangle budget.
///
/// A warning rather than an error, and the reason is the definition: a model
/// twice its budget loads on every engine there is and then holds thirty frames
/// where the profile was written for sixty. Nothing refuses to open it, so
/// nothing here refuses to write it.
ExportIssue? _budget(ModelProject project) {
  final drawn = project.triangleCount;
  final allowed = project.profile.maxTriangles;
  return drawn <= allowed
      ? null
      : ExportIssue(
          ExportSeverity.warning,
          'the project draws $drawn triangles and the ${project.profile.name} '
          'profile allows $allowed; it will load and it will cost frames',
        );
}

List<ExportIssue> _issuesWith(
  ModelObject object, {
  required bool trianglesOnly,
}) => <ExportIssue>[
  // An error, and the loader is the reason rather than taste: a primitive with
  // no indices is a mesh some glTF readers reject outright and the rest draw as
  // nothing, and either way the object is in the outliner and not in the game.
  if (object.geometry.triangleCount == 0)
    ExportIssue(
      ExportSeverity.error,
      '"${object.name}" has no faces; it would be written as an empty mesh, '
      'which some loaders refuse and the rest draw as nothing',
      object: object,
    ),
  ...switch (object.geometry) {
    // Deliberately nothing. A shape that still knows it is a cylinder is built
    // on the way out — `ParametricShape.drawn` — so it exports as well as any
    // mesh does, and an issue saying "this is still parametric" would be an
    // issue telling somebody to throw away the parameters that let them change
    // the segment count. Do not add one.
    ParametricGeometry() => const <ExportIssue>[],
    // Buffers with no topology behind them: there are no half-edges to walk,
    // so the checks below have nothing to ask. Triangles are what arrived and
    // triangles are what will be written.
    ImportedGeometry() => const <ExportIssue>[],
    EditedGeometry(:final EditMesh mesh) => _meshIssues(
      object,
      mesh,
      trianglesOnly: trianglesOnly,
    ),
  },
];

List<ExportIssue> _meshIssues(
  ModelObject object,
  EditMesh mesh, {
  required bool trianglesOnly,
}) {
  final checks = MeshChecks(mesh);
  return <ExportIssue>[
    ?(trianglesOnly ? _wideFaces(object, mesh) : null),
    // An error: a face standing on no area has no normal either, so a
    // triangulated export writes a triangle whose normal is a division by zero.
    // That is a NaN in a vertex buffer, and a NaN in a position or a normal is
    // a model that disappears on some drivers and takes the draw call with it.
    if (checks.degenerateFaces() case final MeshIssue issue)
      ExportIssue(
        ExportSeverity.error,
        '"${object.name}" has ${_count(issue.ids.length, 'face', 'faces')} '
        'with no area; they have no normal either, and what gets written for '
        'them is arithmetic nothing downstream can use',
        object: object,
      ),
    // A warning: triangles are triangles, so a surface pinched at a point
    // uploads and draws. What it breaks is everything that assumes a
    // neighbourhood — smoothing, thickening, printing — and the vertex normal
    // at the pinch, which is averaged across two sheets that face different
    // ways and shades as a dark spot.
    if (checks.nonManifoldVertices() case final MeshIssue issue)
      ExportIssue(
        ExportSeverity.warning,
        '"${object.name}" has '
        '${_count(issue.ids.length, 'vertex', 'vertices')} where two pieces '
        'of surface meet at a point and are joined nowhere else; the shading '
        'there will be wrong and nothing downstream can thicken or subdivide '
        'it',
        object: object,
      ),
    // A warning for the same reason: it loads. With backface culling on, which
    // is every engine's default, an inside-out shell is a model you can see
    // straight through to the inside of, and it is the far side you see.
    if (checks.invertedShells() case final MeshIssue issue)
      ExportIssue(
        ExportSeverity.warning,
        '"${object.name}" has ${_count(issue.ids.length, 'face', 'faces')} in '
        'a closed shell wound inside out; with backface culling on, which is '
        'every engine default, you will see through it to the far side',
        object: object,
      ),
  ];
}

/// "1 face" and "2 faces", because a panel that says "1 faces" reads as
/// something a program wrote rather than as a sentence, and every one of these
/// messages is read by somebody deciding whether to care.
String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Faces the target format has no way to write.
///
/// **`MeshChecks.ngons` is next door and is not this**, which is the one place
/// worth being explicit about: that check asks for more than *four* corners,
/// because a quad is a normal thing to have in a modeller and in a file. A
/// format that holds triangles and nothing else has no room for the quad
/// either, so the question here is a different one and the number is different
/// by one.
///
/// A warning: the writer cuts them, so the file loads. What it cannot promise
/// is that the cut is the one somebody would have made — a fan through a
/// concave face crosses the outside of it, and a non-planar quad cut along the
/// other diagonal is a different shape from the one on screen.
///
/// The walk is over the slots and the liveness test is load-bearing, because
/// `valencyOf` answers a dead slot with the corners it had while it was alive.
/// A mesh somebody has deleted a quad from keeps that slot and its four, so
/// counting the slots would warn about a face that is no longer in the file and
/// send them looking for it. `faceCount` cannot be walked instead: it says how
/// many faces are live while saying nothing about which slots they sit in, and
/// the ids on either side of a tombstone stay where they were.
ExportIssue? _wideFaces(ModelObject object, EditMesh mesh) {
  final wide = <int>[
    for (var face = 0; face < mesh.faceSlotCount; face++)
      if (mesh.isFaceAlive(face) && mesh.valencyOf(face) > 3) face,
  ].length;
  return wide == 0
      ? null
      : ExportIssue(
          ExportSeverity.warning,
          '"${object.name}" has ${_count(wide, 'face', 'faces')} with more '
          'than three sides and the target format holds only triangles; the '
          'export will cut them, and it may not cut them the way you would',
          object: object,
        );
}
