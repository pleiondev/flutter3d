import 'pass_contributor.dart';

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

  void encode(ContributorFrame frame);
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
    _ordered = List<PassContributor>.of(_plugins)
      ..sort(
        (PassContributor a, PassContributor b) => a.order.compareTo(b.order),
      );
  }
}
