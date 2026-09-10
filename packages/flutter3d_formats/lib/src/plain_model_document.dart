import 'animation/animation_clip.dart';
import 'model_document.dart';

/// A [ModelDocument] assembled by hand, from plain lists.
///
/// **The one fake every writer's test needs, so there is one of it.** A test
/// of a writer wants a document that came from nowhere in particular — no
/// decoder, no file — and before this each writer's test file declared its own
/// private `_Document` doing exactly that, field for field the same as the
/// next one's. Two copies of a class are two places a third field can be added
/// to one and forgotten in the other.
///
/// [nodes] defaults to empty rather than to [ModelDocument]'s own "one node per
/// surface" fallback, so a document built here has exactly the fields it was
/// given and nothing a later change to that fallback could move underneath a
/// test that never asked for it. A test of the fallback itself constructs
/// [ModelDocument] some other way.
final class PlainModelDocument extends ModelDocument {
  const PlainModelDocument({
    this.surfaces = const <ModelSurface>[],
    this.materials = const <SurfaceMaterial>[],
    this.images = const <EncodedImage>[],
    this.nodes = const <ModelNode>[],
    this.animations = const <AnimationClip>[],
    this.skins = const <ModelSkin>[],
    this.warnings = const <String>[],
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<SurfaceMaterial> materials;

  @override
  final List<EncodedImage> images;

  @override
  final List<ModelNode> nodes;

  @override
  final List<AnimationClip> animations;

  @override
  final List<ModelSkin> skins;

  @override
  final List<String> warnings;
}
