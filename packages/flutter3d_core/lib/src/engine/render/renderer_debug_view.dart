/// Debug views per draw, the two-channel wipe and overlays that follow it —
/// `A5.21`, `A5.22`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **What `FragInfo.debug_view` holds.** x is the view right of the wipe, y
/// the wipe's column in the scene target's pixels, z the view left of it,
/// and w the draw's identity: the node, the material, and whether the
/// material has a normal map, packed below 2^24 so a 32-bit float holds them
/// exactly. The frame's three are worked out once, in [_beginDebugViews];
/// [_writeDebugViewFor] copies them into the block before each lit draw, or
/// puts a subtree's own view on both sides in their place.
part of 'renderer.dart';

extension _DebugViews on Renderer {
  /// The frame's views, for a scene target [targetWidth] pixels wide —
  /// the scene's and not the output's under a render scale.
  void _beginDebugViews(RenderSettings settings, int targetWidth) {
    final debug = settings.debugView;
    _debugFrame
      ..[0] = debug.showsRight ? debug.view.code : 0.0
      ..[1] = debug.split.clamp(0.0, 1.0) * targetWidth
      ..[2] = debug.showsLeft ? debug.left.code : 0.0;
    _debugSubtreeShown = false;
    _debugSuppressed = false;
    _fragInfo.debugView
      ..[0] = _debugFrame[0]
      ..[1] = _debugFrame[1]
      ..[2] = _debugFrame[2]
      ..[3] = 0.0;
  }

  /// Fills `FragInfo.debug_view` for one lit draw of [node] through
  /// [material]: the frame's views, or the subtree's own on both sides.
  void _writeDebugViewFor(SceneNode node, RenderMaterial material) {
    final block = _fragInfo.debugView;
    if (_debugSuppressed) {
      block.fillRange(0, 4, 0.0);
      return;
    }
    final own = node.debugViewInHierarchy;
    if (own == null) {
      block
        ..[0] = _debugFrame[0]
        ..[1] = _debugFrame[1]
        ..[2] = _debugFrame[2];
    } else {
      block
        ..[0] = own.code
        ..[1] = 0.0
        ..[2] = own.code;
      if (own != DebugView.off) _debugSubtreeShown = true;
    }
    block[3] = block[0] < 0.5 && block[2] < 0.5
        ? 0.0
        : _debugIdentity(node, material);
  }

  /// Draws from here until the next scene pass keep the light: a reflection
  /// or a probe shows the light whatever the frame's views, because it is
  /// part of the picture being debugged and a view baked into a probe would
  /// outlive the frame that asked for it. Subtree views included.
  void _suppressDebugViews() {
    _debugSuppressed = true;
    _fragInfo.debugView.fillRange(0, 4, 0.0);
  }

  /// `CompositeInfo.lens.y`: which sides of the wipe hold display values —
  /// one the right, two the left, three both, nought neither. A subtree's
  /// own channel shows on either side, so a frame that drew one passes both
  /// through.
  double _debugCompositeSides(DebugViewSettings debug) {
    if (_debugSubtreeShown) return 3.0;
    return switch ((debug.showsLeft, debug.showsRight)) {
      (true, true) => 3.0,
      (true, false) => 2.0,
      (false, true) => 1.0,
      (false, false) => 0.0,
    };
  }

  /// The part of [rect] an overlay may draw in under [debug]'s wipe, in a
  /// target [targetWidth] pixels wide, or [rect] itself when the overlays
  /// cover the whole frame. Never empty: a side the view does not reach
  /// is a one-pixel sliver at its edge rather than a zero-sized scissor,
  /// which some backends refuse.
  ScreenRect _overlayScissor(
    DebugViewSettings debug,
    ScreenRect rect,
    int targetWidth,
  ) {
    if (debug.overlays == DebugWipeSide.both) return rect;
    final column = (debug.split.clamp(0.0, 1.0) * targetWidth).round();
    final (from, to) = switch (debug.overlays) {
      DebugWipeSide.left => (rect.x, math.min(rect.x + rect.width, column)),
      _ => (math.max(rect.x, column), rect.x + rect.width),
    };
    final start = math.min(from, rect.x + rect.width - 1);
    return ScreenRect(
      x: start,
      y: rect.y,
      width: math.max(1, to - start),
      height: rect.height,
    );
  }
}

/// [node] and [material] packed as `FragInfo.debug_view.w` reads them: the
/// node's identity in the top eleven bits, the material's in the next
/// twelve, the normal map in the lowest. Identity hashes, so the colours
/// hold for the life of the objects and not across runs.
double _debugIdentity(Object node, RenderMaterial material) {
  final object = _mixIdentity(identityHashCode(node)) & 0x7FF;
  final materialKey = _mixIdentity(identityHashCode(material)) & 0xFFF;
  final normalMapped = material.normal != null ? 1 : 0;
  return (object * 8192 + materialKey * 2 + normalMapped).toDouble();
}

/// Spreads an identity hash's bits, so two objects made one after the other
/// do not land on neighbouring keys.
int _mixIdentity(int hash) {
  final mixed = (hash ^ (hash >> 16)) * 0x45d9f3b;
  return (mixed ^ (mixed >> 16)) & 0x3FFFFFFF;
}
