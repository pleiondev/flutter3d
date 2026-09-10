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

import 'package:flutter3d_formats/flutter3d_formats.dart';

/// One material in a project's table.
///
/// A wrapper around [SurfaceMaterial] for the sake of [version], which is the
/// same bargain [ModelObject.version] makes: a pool holding uploaded textures
/// needs to know that a material changed, and asking it to compare two
/// materials — five texture bindings, a sampler each — costs more than the
/// upload it would save.
final class ProjectMaterial {
  const ProjectMaterial({required this.surface, this.version = 1});

  /// How the surface looks, in the one description every decoder in the
  /// repository produces and every writer takes. Its [TextureBinding]s index
  /// [ModelProject.images].
  final SurfaceMaterial surface;

  /// Bumped by every change. See the class comment.
  final int version;

  /// A copy with a new [surface] and [version] moved on.
  ProjectMaterial withSurface(SurfaceMaterial next) =>
      ProjectMaterial(surface: next, version: version + 1);

  @override
  String toString() =>
      'ProjectMaterial(${surface.name ?? 'unnamed'}, v$version)';
}
