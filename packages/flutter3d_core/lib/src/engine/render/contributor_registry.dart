import 'package:vector_math/vector_math.dart' show Aabb3;

import 'pass_contributor.dart';
import 'render_view.dart';

/// Something that draws inside a pass it does not own.
///
/// The seam exists because `render()` was growing a parameter per feature —
/// first the weapon view model, then the particles — and positional audio,
/// decals and a fog volume would each have added another. A parameter list is
/// a registry with no ordering and no way for an application to add to it.
///
/// Modelled on Flame's components: the engine owns the loop and the
/// contributor owns what it draws. What it does *not* have any more is a
/// stage, because the two stages turned out to be two different things. A
/// contributor draws into the scene's pass, before it is submitted. Anything
/// that wanted its own pass was never a contributor at all — it is a
/// `RenderNode`, and the weapon view model has moved.
abstract base class PassContributor {
  const PassContributor();

  /// Lower encodes first. Ties keep registration order.
  int get order => 0;

  /// Whether there is anything to draw this frame. Checked before [encode] so
  /// a contributor with nothing to say costs no pass setup.
  bool get isActive => true;

  /// Whether [encode] wants the opaque scene's depth to read —
  /// [ContributorFrame.sceneDepth]. False by default, and false costs
  /// nothing.
  ///
  /// **True changes how the frame is drawn**, which is why it is asked
  /// rather than offered to everyone. A contributor draws inside the scene
  /// pass, and the depth it would read is an attachment of that same pass, so
  /// it cannot be sampled there. A frame with a contributor that says true
  /// splits as a frame with glass does (`M3`): the opaque half first, and
  /// this contributor in a pass of its own after the transparent half, with
  /// the surface buffer bound instead of attached. That gives up
  /// multisampling for the frame, as any reader of the surface buffer does.
  bool get readsSceneDepth => false;

  /// Whether what [encode] draws is an overlay on the picture rather than
  /// part of it — a wireframe, a grid, a gizmo — `A5.22`. False by default.
  ///
  /// True confines it to the side of a debug wipe that
  /// `DebugViewSettings.overlays` names: the scene pass narrows the scissor
  /// before [encode] and widens it after, so a contributor that draws
  /// through `PassState` without a scissor of its own needs nothing else.
  bool get isOverlay => false;

  void encode(ContributorFrame frame);

  /// Where [encode] will draw in [view] this frame, in scene space (float32,
  /// relative to `Scene.origin`, the space the view's camera and every
  /// node's `worldMatrix` are in), or null when this contributor cannot say.
  ///
  /// Asked while `RenderSettings.reversedDepth` fits the view's near plane
  /// to what the view draws, and only of a contributor that [isActive]. The
  /// near plane is moved out to just in front of the nearest box anything
  /// drawn in the view gives, so a contributor that draws nearer than every
  /// mesh — smoke at the lens, a muzzle flash — has to be counted or it is
  /// cut away. **Null is the safe answer, and the default**: the view keeps
  /// the camera's own near plane, which is the picture before fitting
  /// existed. A box whose minimum lies past its maximum on any axis says the
  /// contributor draws nothing in [view].
  Aabb3? boundsFor(RenderView view) => null;

  /// Marks where this contributor's draws cover the frame, for the temporal
  /// resolve to keep less history there — `R4`. Called only while the
  /// resolve runs with `TemporalSettings.reactive` above nought, after
  /// [encode] has drawn the same frame.
  ///
  /// Nothing by default: a contributor that draws solid geometry, which the
  /// velocity can follow, has nothing to mark. One that draws what blends —
  /// particles, splats, anything without a depth of its own — redraws it here
  /// through [ReactiveFrame.spriteStage] or a stage of its own.
  void encodeReactive(ReactiveFrame frame) {}

  /// Drops every pipeline this contributor has linked, so its next frame
  /// links them again from whatever the stages are now.
  ///
  /// `Renderer.relinkShaders` calls it on each contributor after dropping its
  /// own: a hot reload swaps the code behind a stage and keeps the handle,
  /// and a pipeline built from the old code would go on drawing it. Nothing
  /// by default, for a contributor that links nothing of its own.
  void relinkShaders() {}
}

/// The contributors a renderer draws, and the order it draws them in.
///
/// Its own class rather than three fields on `Renderer` because ordering is
/// the whole substance of a registry and the only part worth testing — and
/// testing it through the renderer would need a GPU context to ask a question
/// that is pure list arithmetic.
final class ContributorRegistry {
  final List<PassContributor> _plugins = <PassContributor>[];
  List<PassContributor> _ordered = const <PassContributor>[];

  /// Registration order, which is not drawing order — see [active].
  List<PassContributor> get all => List<PassContributor>.unmodifiable(_plugins);

  int get length => _plugins.length;

  T add<T extends PassContributor>(T plugin) {
    _plugins.add(plugin);
    _reorder();
    return plugin;
  }

  bool remove(PassContributor plugin) {
    final removed = _plugins.remove(plugin);
    if (removed) _reorder();
    return removed;
  }

  void clear() {
    _plugins.clear();
    _ordered = const <PassContributor>[];
  }

  /// Everything active, in drawing order.
  ///
  /// [PassContributor.isActive] is asked here rather than by the caller so a
  /// contributor with nothing to say this frame costs no pass setup.
  Iterable<PassContributor> get active sync* {
    for (final plugin in _ordered) {
      if (plugin.isActive) yield plugin;
    }
  }

  void _reorder() {
    // Sorted by order alone, and stably, so two plugins claiming the same
    // number keep the order they were registered in — the only tie-break an
    // application can actually control. Recomputed on change rather than per
    // frame: the set moves once at startup and the frame runs sixty times a
    // second.
    //
    // Stability is arranged rather than assumed: `List.sort` promises none,
    // and past a few dozen entries it is a quicksort that reorders ties. The
    // registration index is the tie-break, so the promise holds at any size.
    final indexed =
        <(int, PassContributor)>[
          for (var i = 0; i < _plugins.length; i++) (i, _plugins[i]),
        ]..sort(((int, PassContributor) a, (int, PassContributor) b) {
          final byOrder = a.$2.order.compareTo(b.$2.order);
          return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
        });
    _ordered = <PassContributor>[for (final (_, plugin) in indexed) plugin];
  }
}
