/// What a click in the viewport selects, and what it refuses to select.
///
/// **The renderer answers a pixel with a `MeshNode`, and a `MeshNode` is not
/// what a person clicked on.** It is one node of several the scene draws at
/// that pixel — the cube of a project, an arm of an imported model, an arrow
/// of the transform gizmo, a bar of the grid — and only some of those are
/// things the document has an opinion about. Turning the node into an answer
/// is this file's whole job, and it is deliberately three answers rather than
/// two: the model was hit, the viewport's own furniture was hit, or nothing
/// was hit. Collapsing the middle case into "nothing" is the bug this exists
/// to prevent — see [PickedService].
///
/// Everything here is a function of values that are passed in. Nothing reaches
/// for a renderer, a document or a cubit, because the interesting half of
/// picking is arithmetic that a test can drive a hundred times a second, and
/// the half that needs a GPU is the one line the caller writes:
/// `objectUnder(await renderer.pickPixel(u, v))`.
library;

import 'package:flutter3d/flutter3d.dart';

/// The layer bits the modeller gives its own nodes.
///
/// **A bit on the node rather than a name, and high rather than low.** The
/// exclusion rule below has to survive a person renaming the gizmo's arrow to
/// `X` and has to survive somebody adding a fourth arrow, so it cannot be a
/// string comparison; `SceneNode.layerMask` is the field that already exists
/// for saying what kind of node this is, it is already consulted by
/// `RenderView`, and it travels with the node when the node is reparented.
///
/// [service] is bit 30 and not bit 1 because the low bits are spoken for:
/// `RenderView.layerMask` is how a split viewport shows one thing on the left
/// and another on the right, and those views will be assigned bits from the
/// bottom. A picking flag sitting at bit 1 would be a flag somebody reroutes a
/// viewport with by accident. Bit 31 is left alone too — this application runs
/// in a browser, where `int` is thirty-two bits once a shift touches it, and
/// the sign bit is not a place to keep a flag.
abstract final class ModelerLayers {
  /// Bit 0, which is what `SceneNode.layerMask` already starts as. Named so
  /// that a node meaning to be pickable can say so rather than leaving the
  /// default and hoping.
  static const int object = 1;

  /// A node the viewport draws for its own sake: a gizmo, the grid, a light's
  /// marker. Set with [markService].
  static const int service = 1 << 30;
}

/// Marks [node] and everything under it as the viewport's own furniture.
///
/// Or-ed into the mask rather than assigned, because a node may already be on
/// a layer for a reason — a gizmo drawn only into the second viewport keeps
/// that bit and gains this one. The subtree comes along without being visited:
/// [isService] walks the parents, so tagging the holder is enough and adding a
/// fourth arrow under it cannot forget.
void markService(SceneNode node) => node.layerMask |= ModelerLayers.service;

/// Whether [node] or anything above it is the viewport's own furniture.
///
/// Up the parents rather than at the node alone, because what the picking pass
/// answers is the leaf that was rasterised: one cone of one arrow, one bar of
/// the grid, one mesh of the model a light's marker was built from. What was
/// tagged is the holder those hang under. `SceneDressing.isMarker` in the
/// editor application walks the same chain for the same reason.
bool isService(SceneNode? node, {int serviceLayers = ModelerLayers.service}) {
  for (var at = node; at != null; at = at.parent) {
    if ((at.layerMask & serviceLayers) != 0) return true;
  }
  return false;
}

/// What was under the pixel.
///
/// Sealed and three-cased. A nullable [PickedObject] would say "an object" or
/// "not an object", and the second answer would have to do for both the
/// background and the gizmo — which are opposite instructions. Clicking the
/// background clears the selection; clicking the gizmo's arrow is the first
/// half of a drag of the very object that is selected, and clearing there
/// would delete the selection out from under the drag that was starting. The
/// compiler asking about a third case at every `switch` is the point.
sealed class PickResult {
  const PickResult();
}

/// A part of the model was under the pixel.
///
/// [id] is the seam to the document. It is `Object?` and not a `ModelObject`
/// because `ModelObject` is doc-03's name for a value with a stable id, a
/// version and a geometry, and this file cannot wait for it; when it arrives,
/// the map from node to object is passed to [objectUnder] as `identify` and
/// this type does not change. Until then there is no document and no id, and
/// [identity] falls back to the node — which is the right answer for a project
/// that is one cube, since a node reference survives the rename that a node's
/// name does not.
///
/// **Equality is by [identity] rather than by [node]**, which matters as soon
/// as anything is imported. One object of a document is drawn as several
/// nodes — glTF splits a mesh at every material boundary — and a selection
/// that compared nodes would hold the same object twice, highlight it twice
/// and offer two transform gizmos for it.
final class PickedObject extends PickResult {
  const PickedObject(this.node, {this.id});

  /// The node the renderer answered with: the leaf that was rasterised.
  ///
  /// Kept alongside [id] because the two questions differ. What to select is
  /// [identity]; where to put the gizmo, and which world matrix to drag, is
  /// [node].
  final SceneNode node;

  /// What the document calls the object this node was drawn for, if a document
  /// was asked. Null when nothing mapped the node, which is every pick until
  /// `scene_sync.dart` exists.
  final Object? id;

  /// What a selection compares. See the class comment.
  Object get identity => id ?? node;

  @override
  bool operator ==(Object other) =>
      other is PickedObject && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'PickedObject($identity)';
}

/// Something the viewport draws for itself was under the pixel.
///
/// **The case that makes a gizmo usable.** An arrow of the transform gizmo is
/// drawn over the object it moves, so every drag of that object begins with a
/// click whose frontmost mesh is the arrow. Answering that click with the
/// object behind the arrow would be worse than answering with the arrow: with
/// two objects selected, a drag of the gizmo would silently drop one of them
/// to whatever happens to be behind it. So the click is refused, and the
/// selection it did not describe is left exactly as it was.
final class PickedService extends PickResult {
  const PickedService(this.node);

  /// The node that was drawn there. The tag that got it refused may be on this
  /// node or on any of its ancestors; [isService] is the question, and view-12
  /// walks the parents itself when it needs to know which gizmo an arrow is a
  /// part of.
  final SceneNode node;

  @override
  String toString() => 'PickedService(${node.name ?? 'unnamed'})';
}

/// The background was under the pixel.
const PickedNothing pickedNothing = PickedNothing._();

/// Nothing was drawn at the pixel. Use [pickedNothing].
final class PickedNothing extends PickResult {
  const PickedNothing._();

  @override
  String toString() => 'PickedNothing()';
}

/// Turns the node `Renderer.pickPixel` answered with into what the application
/// selects.
///
/// [identify] is how a document says which of its objects a node belongs to,
/// and it is expected to walk the parents the way `SceneDressing.handleFor`
/// does — the node handed to it is a leaf. **Returning null from it is a
/// refusal, not a fallback**: a node the document does not claim is, by
/// definition, something the viewport put there for its own reasons, and the
/// alternative — falling back to selecting the raw node — is how "I selected
/// the grid" happens. With no [identify] at all, every node that is not tagged
/// is an object, which is what the phase-0 scene of one cube wants.
///
/// The layer bit is checked before [identify] because the two disagree in a
/// way worth resolving one way for good: a gizmo built out of an instantiated
/// model would be registered by whatever code instantiated it, and the tag is
/// the more local statement of intent.
PickResult objectUnder(
  SceneNode? picked, {
  int serviceLayers = ModelerLayers.service,
  Object? Function(SceneNode node)? identify,
}) {
  if (picked == null) return pickedNothing;
  if (isService(picked, serviceLayers: serviceLayers)) {
    return PickedService(picked);
  }
  if (identify == null) return PickedObject(picked);
  final id = identify(picked);
  return id == null ? PickedService(picked) : PickedObject(picked, id: id);
}

/// The selection [pick] leaves behind, given the selection it found.
///
/// The four rules, and why each is the one people expect:
///
///  * A plain click on an object replaces the selection. Anything else means
///    the only way back to one object is a click on empty space first, and a
///    modeller full of objects has no empty space to click on.
///  * A shift-click on an object that is not selected adds it.
///  * **A shift-click on an object that is already selected removes it.** The
///    modifier is the gesture people already have for "amend this selection",
///    and adding twice does nothing, so a shift-click that only ever added
///    would waste the one gesture that can undo a mis-click. Without it,
///    dropping one object from a selection of thirty means building the other
///    twenty-nine again.
///  * A click on nothing clears, unless shift is held, in which case it keeps
///    what there was: with the modifier down the person is composing a
///    selection, and a slip onto the background in the middle of composing it
///    should cost nothing.
///
/// [PickedService] is not in that list because it changes nothing at all, with
/// or without the modifier — see [PickedService].
///
/// The result is unmodifiable, and a copy even when it holds the same
/// members. Returning [selection] itself would hand back a set the caller may
/// still be mutating, and the reference then aliases whatever the caller does
/// next; the sets here hold one object or a handful, so the copy is not worth
/// a subtle bug. Insertion order is kept, so the last member is the one picked
/// last — which is what a tool needing a single object should read.
Set<PickedObject> applyPick(
  Set<PickedObject> selection,
  PickResult pick, {
  required bool extend,
}) => Set<PickedObject>.unmodifiable(switch (pick) {
  PickedService() => selection,
  PickedNothing() => extend ? selection : const <PickedObject>{},
  PickedObject() when !extend => <PickedObject>{pick},
  PickedObject() when selection.contains(pick) => selection.where(
    (PickedObject held) => held != pick,
  ),
  PickedObject() => <PickedObject>[...selection, pick],
});
