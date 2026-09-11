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

import 'dart:math';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'image_dimensions.dart';
import 'material.dart';
import 'project.dart';
import 'texture_budget.dart';

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
  /// than three sides, and [requireManifold] says whether a pinched vertex
  /// stops the export rather than merely spoiling it. Both default to
  /// `null`, which reads [ProjectProfile.requireTriangles] and
  /// [ProjectProfile.requireManifold] — the profile is about the machine that
  /// will draw the model, and that is what "will this format hold a quad" and
  /// "must this be watertight" both are. An explicit `true`/`false` still
  /// wins: a single write to OBJ wants `trianglesOnly: false` whatever the
  /// profile says, without a second profile to say it with.
  factory ExportReadiness.check(
    ModelProject project, {
    bool? trianglesOnly,
    bool? requireManifold,
  }) {
    final found = <ExportIssue>[
      // The budget goes first, ahead of the objects, because it is the one
      // fault that is true of all of them at once: a bar that led with a quad
      // in one object while the project as a whole was twelve times its budget
      // would be answering the smaller question. Warnings keep this order
      // through the two passes below, so the position is a choice rather than
      // an accident of where the call sits.
      ?_budget(project),
      // Materials are project-level, the same way the budget is: one row
      // regardless of how many objects paint with it, so this runs once
      // here rather than once per object below.
      ...materialIssues(project),
      // The texture budget, project-level for the same reason: `mat-28`'s
      // own `measure` reads `project.images` whole, not one object's share
      // of it.
      ...textureBudgetIssues(project),
      for (final ModelObject object in project.objects)
        ..._issuesWith(
          object,
          trianglesOnly: trianglesOnly ?? project.profile.requireTriangles,
          requireManifold: requireManifold ?? project.profile.requireManifold,
          maxTextureSize: project.profile.maxTextureSize,
          texelsPerMeter: project.profile.texelsPerMeter,
          materials: project.materials,
          images: project.images,
        ),
    ];
    return ExportReadiness._(_worstFirst(found));
  }

  /// [found], ordered the way [ExportReadiness.check] orders what it finds:
  /// errors first, then warnings, each keeping the order it arrived in.
  ///
  /// For a caller that has the issues already and does not want them found
  /// again — `ReadinessCache` keeps them per object against the object's
  /// version, and needs the same ordering rule without the walk. Sharing the
  /// rule rather than copying it is the point: two orderings that agree today
  /// are two orderings that stop agreeing the first time one of them changes.
  factory ExportReadiness.of(List<ExportIssue> found) =>
      ExportReadiness._(_worstFirst(found));

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

/// [found] with the errors first, by two passes rather than by a sort.
///
/// `List.sort` is not stable, so sorting on the severity alone would let two
/// warnings swap places between runs and a panel reorder itself while nothing
/// changed.
List<ExportIssue> _worstFirst(List<ExportIssue> found) => <ExportIssue>[
  for (final ExportIssue issue in found)
    if (issue.severity == ExportSeverity.error) issue,
  for (final ExportIssue issue in found)
    if (issue.severity == ExportSeverity.warning) issue,
];

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
  required bool requireManifold,
  required int maxTextureSize,
  required double? texelsPerMeter,
  required List<ProjectMaterial> materials,
  required List<EncodedImage> images,
}) => <ExportIssue>[
  // An error, and the loader is the reason rather than taste: a primitive with
  // no indices is a mesh some glTF readers reject outright and the rest draw as
  // nothing, and either way the object is in the outliner and not in the game.
  //
  // A socket is exempted on purpose: it draws nothing *because* it is a named
  // point rather than a shape, the same way an empty group already writes as
  // a node with no surface, and warning about geometry nobody meant to add
  // would send somebody hunting for faces that were never supposed to exist.
  if (object.geometry.triangleCount == 0 &&
      object.geometry is! SocketGeometry)
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
    // so the mesh checks below have nothing to ask — triangles are what
    // arrived and triangles are what will be written. Morph targets are the
    // one thing an imported mesh can carry that an edited or parametric one
    // cannot yet, so they are the one thing checked here instead.
    ImportedGeometry(:final data) => _morphTargetIssues(
      object,
      data,
      maxTextureSize,
    ),
    EditedGeometry(:final EditMesh mesh) => <ExportIssue>[
      ..._meshIssues(
        object,
        mesh,
        trianglesOnly: trianglesOnly,
        requireManifold: requireManifold,
      ),
      ?_texelDensityIssue(
        object,
        mesh,
        texelsPerMeter: texelsPerMeter,
        materials: materials,
        images: images,
      ),
    ],
    // Deliberately nothing, and for the same reason the check above exempts
    // it: a socket has no faces on purpose.
    SocketGeometry() => const <ExportIssue>[],
  },
];

/// How densely [object]'s texture covers its own surface, against the
/// profile's [texelsPerMeter] target — `doc-35n`'s own rule.
///
/// **Silent whenever there is nothing to measure, on purpose**: no target set
/// ([texelsPerMeter] null), no material on the object's first slot, no base
/// colour texture on that material, an image whose header will not read, or
/// a mesh with no UV island of its own — every corner an [EditMesh] has not
/// been given a UV sits at `Vector2.zero()`, which folds the whole face flat
/// and gives it zero UV area, so "no UV" and "degenerate UV" both read as the
/// same silence rather than as a division by zero. Any one of those is "there
/// is no picture stretched over this object to measure", a different fact
/// from "the picture is the wrong size for it".
///
/// **One material only, the object's own first slot** — the same
/// simplification `project_document.dart`'s own `_slotOf` already makes and
/// for the same reason it gives: an object is one draw call today, so asking
/// which of several materials to measure is a question nothing can have set
/// up yet.
///
/// The number itself is the texel-density formula this shape of check
/// already goes by elsewhere: a texture's own resolution, scaled by how much
/// of the unit UV square a piece of surface takes up against how much of the
/// object's actual surface it is — `resolution × √(uvArea) ÷ √(worldArea)`.
/// Both areas come from the same fan-triangulation `EditMesh.areaOf` already
/// walks for world space, done again here over `uvOf` for UV space, since
/// `areaOf` itself has no UV-space twin to call instead.
///
/// A factor of two off target either way is the threshold, not a return to
/// exactly [texelsPerMeter]: `mat-28`'s own texture presets already differ by
/// that much between targets, so a check that fired on any deviation at all
/// would be a check nobody could satisfy on every profile at once.
ExportIssue? _texelDensityIssue(
  ModelObject object,
  EditMesh mesh, {
  required double? texelsPerMeter,
  required List<ProjectMaterial> materials,
  required List<EncodedImage> images,
}) {
  if (texelsPerMeter == null || object.materialSlots.isEmpty) return null;
  final slot = object.materialSlots.first;
  if (slot < 0 || slot >= materials.length) return null;
  final texture = materials[slot].surface.baseColorTexture;
  if (texture == null ||
      texture.imageIndex < 0 ||
      texture.imageIndex >= images.length) {
    return null;
  }
  final dimensions = imageDimensions(images[texture.imageIndex].bytes);
  if (dimensions == null) return null;

  var worldArea = 0.0;
  var uvArea = 0.0;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    worldArea += mesh.areaOf(face);
    uvArea += _uvAreaOf(mesh, face);
  }
  if (uvArea <= 0 || worldArea <= 0) return null;

  final resolution = sqrt(
    dimensions.width.toDouble() * dimensions.height.toDouble(),
  );
  final actual = resolution * sqrt(uvArea) / sqrt(worldArea);
  final ratio = actual / texelsPerMeter;
  if (ratio < 2.0 && ratio > 0.5) return null;

  return ExportIssue(
    ExportSeverity.warning,
    '"${object.name}" measures ${actual.round()} texels/m against a '
    '${texelsPerMeter.round()} texels/m profile target — '
    '${ratio >= 1 ? 'about ${ratio.toStringAsFixed(1)}× as dense' : 'about ${(1 / ratio).toStringAsFixed(1)}× as sparse'}, '
    'which will read as ${ratio >= 1 ? 'crisper' : 'blurrier'} than the rest '
    'of a scene built to the same target',
    object: object,
  );
}

/// The UV-space twin of [EditMesh.areaOf]: the same fan triangulation, over
/// [EditMesh.uvOf] instead of [EditMesh.positionOf], and a 2D cross product
/// (the shoelace term) instead of a 3D one since a UV island has no third
/// axis to be flat against.
double _uvAreaOf(EditMesh mesh, int face) {
  final corners = <Vector2>[];
  mesh.forEachHalfEdge(face, (int half) => corners.add(mesh.uvOf(half)));
  if (corners.length < 3) return 0;
  final anchor = corners.first;
  var total = 0.0;
  for (var i = 1; i + 1 < corners.length; i++) {
    final bx = corners[i].x - anchor.x;
    final by = corners[i].y - anchor.y;
    final cx = corners[i + 1].x - anchor.x;
    final cy = corners[i + 1].y - anchor.y;
    total += (bx * cy - by * cx).abs() * 0.5;
  }
  return total;
}

/// Morph targets an imported mesh brought in, against the profile's texture
/// limit.
///
/// **`MorphTexture` puts one column on the texture per vertex the mesh has**
/// — see its own doc comment in `flutter3d_geometry` — so a mesh morphing more
/// vertices than [maxTextureSize] allows columns for is a texture the target
/// device refuses to create. The base shape still uploads and draws; what is
/// lost is only the morphing, which is why this is a warning and not an
/// error — the object does not vanish, an animation of its face does nothing.
List<ExportIssue> _morphTargetIssues(
  ModelObject object,
  MeshData data,
  int maxTextureSize,
) {
  if (data.morphTargets.isEmpty || data.vertexCount <= maxTextureSize) {
    return const <ExportIssue>[];
  }
  return <ExportIssue>[
    ExportIssue(
      ExportSeverity.warning,
      '"${object.name}" morphs ${data.vertexCount} vertices and the profile '
      'allows a $maxTextureSize-pixel texture; the morph texture needs one '
      'column a vertex, so it will not build on that target and the shape '
      'will not morph there',
      object: object,
    ),
  ];
}

List<ExportIssue> _meshIssues(
  ModelObject object,
  EditMesh mesh, {
  required bool trianglesOnly,
  required bool requireManifold,
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
    // A warning unless the profile requires a manifold: triangles are
    // triangles, so a surface pinched at a point uploads and draws, and what
    // it breaks — smoothing, thickening, printing, the vertex normal at the
    // pinch — only matters to a profile that asked for a watertight mesh in
    // the first place.
    if (checks.nonManifoldVertices() case final MeshIssue issue)
      ExportIssue(
        requireManifold ? ExportSeverity.error : ExportSeverity.warning,
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

/// [project]'s own images against its `ProjectProfile.textures` budget —
/// `mat-22`'s "texture outside budget," read from `mat-28`'s `measure`
/// rather than a second walk of its own.
///
/// **Project-level, the same way [materialIssues] and [_budget] are**: an
/// image is a row in `project.images` regardless of how many materials
/// sample it, and `measure` already counts each one exactly once for the
/// same reason `project.images` is a deduplicated table at all. Public for
/// the same reason `materialIssues` is — `ReadinessCache.of` calls it
/// directly, once, rather than once per object.
List<ExportIssue> textureBudgetIssues(ModelProject project) {
  final budget = project.profile.textures;
  final usage = measure(project, budget);
  return <ExportIssue>[
    for (final int index in usage.overs)
      ExportIssue(
        ExportSeverity.warning,
        () {
          final label = project.images[index].name == null
              ? 'image $index'
              : 'image $index ("${project.images[index].name}")';
          final dimensions = imageDimensions(project.images[index].bytes);
          return '$label is '
              '${dimensions == null ? 'wider or taller' : '${dimensions.width}×${dimensions.height}'} '
              'and the ${project.profile.name} profile allows '
              '${budget.maxSide}px a side; it will need resizing before it '
              'reaches that target';
        }(),
      ),
    // A warning rather than an error, the same reasoning `_budget` gives for
    // triangles: every image still loads and draws, and what is over is a
    // total the device this profile describes cannot actually hold once
    // everything is uploaded at once.
    if (usage.totalBytes > budget.maxBytesOnDevice)
      ExportIssue(
        ExportSeverity.warning,
        'the project\'s textures cost ${usage.totalBytes} bytes recomputed '
        'as ${budget.targetFormat.name} and the ${project.profile.name} '
        'profile allows ${budget.maxBytesOnDevice}; some of them will not '
        'fit in memory at once on that target',
      ),
  ];
}

/// Every material's own issues, independent of which objects paint with it.
///
/// **Project-level, the same way [_budget] is** — a material is one row
/// regardless of how many objects use it, and reporting it once per object
/// would repeat the same sentence for every object sharing a slot. Public
/// rather than `_`-prefixed so `ReadinessCache.of` can call the identical
/// function directly: unlike the budget, nothing here needs a different
/// shape for the cached path — no aggregation across objects to redo, just
/// `project.materials`, which the cache already has.
List<ExportIssue> materialIssues(ModelProject project) => <ExportIssue>[
  for (var i = 0; i < project.materials.length; i++)
    ..._singleMaterialIssues(i, project.materials[i]),
];

List<ExportIssue> _singleMaterialIssues(int index, ProjectMaterial material) {
  final surface = material.surface;
  final label = surface.name == null
      ? 'material $index'
      : 'material $index ("${surface.name}")';
  return <ExportIssue>[
    // A warning: it loads and draws identically to opaque, so nothing here
    // is broken — it is paid for. Blend costs every engine a sort and the
    // overdraw a transparent surface costs, and a material with no texture
    // to carry alpha and a fully opaque colour of its own pays that for a
    // result nobody can tell from opaque.
    if (surface.alphaMode == SurfaceAlphaMode.blend &&
        surface.baseColorTexture == null &&
        surface.baseColor.w >= 1.0)
      ExportIssue(
        ExportSeverity.warning,
        '$label is set to blend and has no transparency of its own — a '
        'fully opaque colour with no texture to carry alpha — so it costs '
        'the sort and the overdraw a blended surface costs for a result '
        'nobody can tell from opaque; opaque would draw the same thing for '
        'less',
      ),
    // A warning, not an error: the texture is still there and still loads,
    // and `TextureBinding.texCoordSet`'s own doc comment says plainly that
    // only set 0 is decoded — so a binding naming any other set reads from
    // whichever UVs a loader falls back to, or from nothing at all.
    if (_texCoordSetsOf(surface).any((int set) => set != 0))
      ExportIssue(
        ExportSeverity.warning,
        '$label samples a texture coordinate set other than 0; nothing in '
        'this repository decodes any but set 0 today, so that texture will '
        'be read from the wrong UVs once this leaves',
      ),
    // A warning, `mat-22`'s own "`.fmat` без копии": `ProjectMaterial.fmat`
    // names an external shader file this class deliberately never reads —
    // see its own doc comment — so nothing here can tell whether that file
    // defines `extraTextures` or `parameters` `SurfaceMaterial` has no room
    // for. What is knowable without opening it is enough to warn about: a
    // glTF/GLB export writes `surface` and nothing else, so a material
    // still deferring to a file at all is a material an export can only
    // give the base PBR half of.
    if (material.fmat != null)
      ExportIssue(
        ExportSeverity.warning,
        '$label defers to an external file ("${material.fmat}"); a '
        'glTF/GLB export carries only its own colour, metallic, roughness '
        'and texture slots, so any extraTextures or shader parameters that '
        'file defines beyond those are not written',
      ),
  ];
}

/// The `texCoordSet` of every texture slot [surface] actually fills.
Iterable<int> _texCoordSetsOf(SurfaceMaterial surface) => <TextureBinding?>[
  surface.baseColorTexture,
  surface.metallicRoughnessTexture,
  surface.normalTexture,
  surface.occlusionTexture,
  surface.emissiveTexture,
].whereType<TextureBinding>().map((TextureBinding b) => b.texCoordSet);
