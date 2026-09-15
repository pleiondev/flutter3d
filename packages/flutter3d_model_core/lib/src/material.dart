/// What a project paints its objects with.
///
/// **A table on the project rather than a material on the object, because
/// materials are shared and objects are not.** Forty bolts on a machine are one
/// steel; giving each of them its own copy would mean forty edits to darken the
/// steel, forty uploads to draw the change, and forty materials in the file the
/// exporter writes. [ModelObject.materialSlots] indexes this table, so the bolts
/// hold a number each and the steel exists once.
///
/// **The images are a second table beside it, mirroring `ModelDocument`.** Two
/// materials can sample one atlas — a decal sheet used matte in one place and
/// glossy in another — and a texture bound from inside a material would then be
/// uploaded twice. It is also what makes the round trip exact: a decoded
/// document arrives as materials indexing images, and this is the same shape,
/// so importing and exporting move indices about rather than rebuilding them.
library;

import 'package:flutter3d_core/formats.dart';

import 'texture_graph.dart';

/// One material in a project's table.
///
/// A wrapper around [SurfaceMaterial] for the sake of [version], which is the
/// same bargain [ModelObject.version] makes: a pool holding uploaded textures
/// needs to know that a material changed, and asking it to compare two
/// materials — five texture bindings, a sampler each — costs more than the
/// upload it would save.
final class ProjectMaterial {
  const ProjectMaterial({
    required this.surface,
    this.version = 1,
    this.fmat,
    this.graph,
    this.bakedAtVersion,
  });

  /// How the surface looks, in the one description every decoder in the
  /// repository produces and every writer takes. Its [TextureBinding]s index
  /// [ModelProject.images].
  final SurfaceMaterial surface;

  /// Bumped by every change. See the class comment.
  final int version;

  /// A standalone `.fmat` file this material's look defers to, relative to
  /// wherever the project itself is kept.
  ///
  /// **[surface] above is what this material looks like today, not a fallback
  /// that stops mattering once [fmat] is set** — the same shape
  /// `flutter3d_sim`'s `LevelMaterial.fmat` already carries for a level. This
  /// class does not read the file: doing so needs a base path to resolve it
  /// against and a decision about what a read failure means to a project, and
  /// both belong to whatever opens the project — `flutter3d_bridge`'s loader
  /// is the level format's equivalent fork, and a modeller-side one is
  /// `fmt-17`'s. Null is the ordinary case: a material authored entirely in
  /// this project, keeping its own numbers.
  final String? fmat;

  /// What `BakeTextureGraph` bakes into this material's texture slots — one
  /// graph, its `OutputTextureNode`s each naming which slot they feed. Null
  /// for a material painted by hand, the ordinary case; `mat-13`'s own panel
  /// is what a person edits this with node by node, once it exists.
  final TextureGraph? graph;

  /// [version] the last time `BakeTextureGraph` ran, or null if it never has.
  /// See [isGraphStale].
  final int? bakedAtVersion;

  /// Whether [graph] has moved on since the slots were last baked from it —
  /// true right after `SetMaterialGraph` replaces the graph, or after any
  /// other edit bumps [version] past the bake's own. False for a material
  /// with no [graph] at all: nothing to be stale about.
  bool get isGraphStale => graph != null && bakedAtVersion != version;

  /// A copy with a new [surface] and [version] moved on.
  ProjectMaterial withSurface(SurfaceMaterial next) => ProjectMaterial(
    surface: next,
    version: version + 1,
    fmat: fmat,
    graph: graph,
    bakedAtVersion: bakedAtVersion,
  );

  /// A copy naming (or clearing) the `.fmat` this material defers to, with
  /// [version] moved on the same way [withSurface] does.
  ProjectMaterial withFmat(String? next) => ProjectMaterial(
    surface: surface,
    version: version + 1,
    fmat: next,
    graph: graph,
    bakedAtVersion: bakedAtVersion,
  );

  /// A copy naming (or clearing) [graph], with [version] moved on — so a
  /// graph just handed to a material reads [isGraphStale] true until
  /// `BakeTextureGraph` runs against it, the same as any other edit would.
  ProjectMaterial withGraph(TextureGraph? next) => ProjectMaterial(
    surface: surface,
    version: version + 1,
    fmat: fmat,
    graph: next,
    bakedAtVersion: bakedAtVersion,
  );

  /// `BakeTextureGraph`'s own update: a new [surface] with the baked images
  /// wired into their slots, [version] moved on the same one step
  /// [withSurface] would, and [bakedAtVersion] set to that same new version —
  /// so this exact bake reads fresh, and the next edit of any kind, graph or
  /// not, is what makes [isGraphStale] true again.
  ProjectMaterial withBake(SurfaceMaterial next) {
    final baked = version + 1;
    return ProjectMaterial(
      surface: next,
      version: baked,
      fmat: fmat,
      graph: graph,
      bakedAtVersion: baked,
    );
  }

  @override
  String toString() =>
      'ProjectMaterial(${surface.name ?? 'unnamed'}, v$version'
      '${fmat == null ? '' : ', $fmat'})';
}
