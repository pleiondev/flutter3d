/// What the composite shows and how strongly, decided before anything binds.
///
/// Free of any GPU type, like the frame graph and the shadow slot allocator
/// beside it, and for the same reason: the decision is a handful of flags
/// resolving to five values, the debug views it selects are the paths a golden
/// image cannot see, and none of it needs a device to answer.
library;

/// Which picture the composite samples into the scene slot.
///
/// Three exclusive answers where the pass used to have two nested conditionals.
/// They are exclusive on purpose — asking for the shadow map and the surface
/// buffer at once has to resolve to one texture, and writing that down beats
/// discovering it from the order of two `?:`.
enum CompositeView {
  /// The lit scene, tone mapped and exposed. What a frame normally shows.
  scene,

  /// The surface buffer, raw. Also what the point-shadow debug estimate rides
  /// in, because that estimate never leaves the shader otherwise.
  surfaceBuffer,

  /// The directional shadow map, or the cube atlas when there is one.
  shadowMap,
}

/// The composite's five knobs, worked out together.
///
/// Together is the point. The bloom slot is filled whether or not the frame
/// produced a glow — flutter_gpu crashes natively, with no Dart frame to catch,
/// when a sampler the compiled shader declares goes unbound — so with bloom
/// culled the pass binds the scene there instead. That stand-in is only
/// harmless because [bloomIntensity] is zero, and nothing in the shader
/// enforces the pairing: it multiplies whatever is in the slot by whatever is
/// in the uniform. Deciding both here makes them one decision instead of two
/// that have to be kept in step by hand.
///
/// The debug views take the same care. Each of them replaces the picture *and*
/// turns exposure, tone mapping and bloom off, because a debug buffer is data
/// rather than light and any of the three would misreport it.
final class CompositeMix {
  /// Resolves the flags. Named rather than positional because six booleans in a
  /// row is exactly the call site that gets two of them swapped.
  factory CompositeMix({
    required bool showSurfaceBuffer,
    required bool showPointShadowDebug,
    required bool showShadowMap,
    required bool hasShadowView,
    required bool hasGlow,
    required double exposure,
    required double bloomIntensity,
    required bool tonemap,
  }) {
    // The debug picture rides in the surface buffer rather than in an
    // attachment of its own, so asking for the point-shadow estimate is asking
    // to see that buffer.
    final showingSurface = showSurfaceBuffer || showPointShadowDebug;
    // A map nobody allocated cannot be shown, and falling back to the lit scene
    // is better than a black frame.
    final showingShadow = showShadowMap && hasShadowView;
    final raw = showingSurface || showingShadow;

    return CompositeMix._(
      view: showingShadow
          ? CompositeView.shadowMap
          : (showingSurface ? CompositeView.surfaceBuffer : CompositeView.scene),
      usesGlow: hasGlow,
      exposure: raw ? 1.0 : exposure,
      // The half of the pairing the shader can see. Zero whenever the slot does
      // not hold a glow, and zero for a raw view because a debug buffer must
      // come out as the numbers that were written into it.
      bloomIntensity: raw || !hasGlow ? 0.0 : bloomIntensity,
      tonemap: raw || !tonemap ? 0.0 : 1.0,
    );
  }

  const CompositeMix._({
    required this.view,
    required this.usesGlow,
    required this.exposure,
    required this.bloomIntensity,
    required this.tonemap,
  });

  /// Which texture goes in the scene slot.
  final CompositeView view;

  /// Whether the bloom slot holds the frame's glow rather than the stand-in.
  ///
  /// False means the graph culled bloom and the pass binds the scene there. The
  /// invariant that makes that safe is [bloomIntensity] being zero, and
  /// [mixesGlowItDoesNotHave] is that invariant written as a question.
  final bool usesGlow;

  /// Multiplies the scene before tone mapping. One for a raw view.
  final double exposure;

  /// Multiplies the bloom slot. Zero unless [usesGlow].
  final double bloomIntensity;

  /// One to tone map, zero not to. A float because it goes straight into the
  /// uniform the shader compares against a half.
  final double tonemap;

  /// Whether this mix would multiply in a texture that is not a glow.
  ///
  /// Always false, and a test says so for every combination of the flags. It is
  /// here rather than only in the test because the two knobs are set in
  /// different places in the pass and a reader deserves to find the pairing
  /// named.
  bool get mixesGlowItDoesNotHave => !usesGlow && bloomIntensity != 0.0;
}
