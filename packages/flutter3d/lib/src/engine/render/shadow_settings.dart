/// How shadows are cast, and what they cost.
///
/// Its own file rather than a section of `render_settings.dart`: shadows carry a
/// vocabulary nothing else in that file uses — cascades, an atlas, the six faces
/// of a cube map, a static bake — and at nearly three hundred lines they were
/// most of it. Nothing here is private and nothing else reads a field of it, so
/// this is a move rather than a design change.
library;

/// Directional shadow mapping settings.
/// Which faces of a caster are drawn into a shadow map.
///
/// The two ways a shadow map fails are opposites, and this picks which one to
/// risk. Recording the light-facing side means a lit surface is compared
/// against its own depth and shows acne; recording the far side moves the
/// recorded surface inside the solid, which cures the acne and instead lets a
/// thin caster's shadow detach from it.
enum ShadowCasterFaces {
  /// Draw the faces turned towards the light. The general-purpose choice, and
  /// what flutter_scene defaults to; acne is held off by the biases.
  front,

  /// Draw the faces turned away — "second depth". For solid, closed geometry
  /// this removes acne outright, since the recorded distance is the far wall of
  /// the body and the bias hides inside it. This engine's cube pass has always
  /// done this without saying so, which suits a dungeon of blocky brushes.
  back,

  /// Draw both. Records the nearest surface as [front] does for closed bodies,
  /// but also catches a one-sided wall or an open shell, which the other two
  /// see straight through.
  both,
}

final class ShadowSettings {
  const ShadowSettings({
    this.enabled = true,
    this.resolution = 1024,
    this.cubeResolution = 512,
    this.bias = 0.0015,
    this.normalOffset = 0.02,
    this.strength = 1.0,
    this.depthPadding = 1.2,
    this.cascades = 3,
    this.cascadeSplit = 0.7,
    this.viewDistance = 60.0,
    this.pointBias = 0.08,
    this.pointNormalOffset = 1.5,
    this.pointSoftness = 4.0,
    this.pointLightRadius = 0.0,
    this.pointMaxSoftness = 16.0,
    this.casterFaces = ShadowCasterFaces.back,
  });

  /// How many cascades the directional map is split into, one to three.
  ///
  /// **Three by default, at a thousand-pixel tile.** It was one for a while,
  /// and the argument then was compatibility: one cascade is the exact
  /// behaviour this renderer started with, so every recorded golden held. That
  /// argument expired the moment the goldens were re-recorded deliberately —
  /// and it had been paying for itself with a default nobody chose, since both
  /// shipped applications set cascades themselves.
  ///
  /// The pairing with [resolution] is the whole decision, because the atlas is
  /// `resolution × cascades` wide and eight bytes a pixel:
  ///
  /// | setting | atlas | memory |
  /// |---|---|---|
  /// | 1 × 2048 (the old default) | 2048 × 2048 | 33 MB |
  /// | 3 × 2048 (the naive rise) | 6144 × 2048 | 100 MB |
  /// | **3 × 1024 (this)** | 3072 × 1024 | **25 MB** |
  ///
  /// So the default is better *and* cheaper than what it replaced, and the
  /// trap it avoids is the middle row: raising the count without lowering the
  /// tile triples the bill for a picture that is only a little better.
  ///
  /// What they buy: a directional map fitted to the whole scene spends its
  /// resolution on ground the camera cannot see. On a level a hundred and
  /// twenty metres by two hundred and sixty that is about fourteen centimetres
  /// of world per texel, which draws a character's own shadow as a blurred
  /// slab beside them — it was reported as the character being drawn twice.
  /// Three cascades put the nearest one around the camera instead, at metres
  /// per texel rather than tens.
  ///
  /// They are laid out side by side in one texture, so the pass count does not
  /// change and neither does the number of samplers the fragment shader binds.
  ///
  /// A game that raises this raises its atlas with it, so raise [resolution]
  /// only against a measurement: the platformer asks for 2048 and says in the
  /// same breath which shadow it looked at, which is the form that argument has
  /// to take to be worth a hundred megabytes.
  final int cascades;

  /// How the view distance is divided between cascades, from 0 to 1.
  ///
  /// Zero splits them evenly by distance, one splits them logarithmically —
  /// which is what perspective actually wants, since a texel's world size grows
  /// with distance. The usual practical answer is most of the way towards
  /// logarithmic, and that is the default.
  final double cascadeSplit;

  /// How far from the camera the cascades are fitted for, in metres.
  ///
  /// **The number that decides how sharp a character's own shadow is**, and the
  /// reason it exists: without it the cascades are split across the *scene*, so
  /// the near map grows with the level. On a 22 × 118 m level that put the near
  /// cascade at 14.5 m of radius — 3.4 cm of world per texel at 1024 — and a
  /// penguin's shadow came out as a staircase of blocks beside it, which was
  /// reported, twice and in the same words, as the character being drawn twice.
  /// Doubling the level's length made it worse again. That is the defect
  /// cascades were supposed to remove, surviving with a milder constant.
  ///
  /// Sixty metres by default: far enough that the shadows a player can see are
  /// fitted, near enough that the first cascade is tight. **Nothing goes
  /// unshadowed past it** — the last cascade is still fitted to the whole scene
  /// and every fragment falls through to it, so this trades sharpness near the
  /// camera against sharpness far from it, and never against coverage.
  final double viewDistance;

  /// Distance bias for a point light's cube map, in **metres**.
  ///
  /// Metres rather than normalised depth because the cube faces store radial
  /// distance, not clip depth — see shadow_distance.frag for why they have to.
  final double pointBias;

  /// How far along the normal a cube-map sample moves before being projected,
  /// **in texels of the face it lands on**, before the slope term is added.
  ///
  /// **Texels rather than metres, and the unit is the fix.** What this offset
  /// clears is the width of one texel of the shadow map: that texel covers a
  /// patch of surface, records the whole patch at a single distance, and every
  /// fragment in it that is not the point actually measured compares against a
  /// distance from somewhere else. The patch is a solid angle, so it grows with
  /// range — a fixed 2 cm was enough at two metres from a lamp and a third of
  /// what was needed at ten.
  ///
  /// What that looked like: the golden teapot's floor shadowing itself across
  /// everything its lamp reached, ending in a *straight line* where the floor's
  /// own edge projects, because past that edge the atlas holds nothing and
  /// nothing can occlude. A straight edge across a shadow in a scene that has
  /// no straight edges in it.
  ///
  /// One and a half texels, with the slope term on top of it. Below one the
  /// acne returns at grazing angles; far above it the shadow detaches from what
  /// casts it, which is the failure the cap on the slope term exists for.
  final double pointNormalOffset;

  /// Penumbra width for a point light, as a radius in texels of one cube face.
  ///
  /// Zero collapses the kernel to a single tap and a hard edge.
  ///
  /// Texels, not a fraction of the tile, so a penumbra keeps its width when the
  /// atlas resolution changes. The first value tried here was 0.9, which looked
  /// like a reasonable "small" default and did nothing at all: a face is 1024
  /// texels across, so every tap in the disk landed in the same texel as the
  /// centre and returned the same answer. 62 pixels of the whole frame moved.
  /// A kernel measured in texels has to be wider than one.
  ///
  /// Four is measured rather than judged: against an unfiltered edge, a radius
  /// of 2.5 texels moved 69 pixels of the frame and 20 texels moved 4861. The
  /// first is invisible and the second smears a contact shadow, so the default
  /// sits between them, at about the width flutter_scene gives a spot. This is
  /// a fixed radius, and with contact hardening on it becomes the *floor* on
  /// the width rather than the whole story: it is then only how sharp a
  /// contact edge is allowed to get.
  final double pointSoftness;

  /// The emitter's own radius, in metres. Zero uses a fixed kernel instead.
  ///
  /// **Off by default: at this map resolution the extra taps buy about a
  /// pixel.** An honest cost against an honest benefit, not a defect — which
  /// this paragraph used to say it was, and then spent fifty lines below
  /// disproving. The lead sentence is what an IDE tooltip and a generated
  /// dartdoc show, so a working feature was being announced as broken to
  /// everybody who never scrolled.
  ///
  /// What follows is the investigation, kept because its two dead ends are
  /// worth not walking again. It starts from a symptom that is real: the
  /// estimate collapses to [pointSoftness] almost everywhere, and raising this
  /// from 0.05 to 0.6 — twelve times — moves twenty pixels of the frame, where
  /// the width should scale with it directly.
  ///
  /// Two explanations were written down and both were measured wrong, which is
  /// worth recording so they are not proposed again:
  ///
  /// * *The blocker search finds the receiver's own floor.* No: the atlas holds
  ///   the caster only. `cube-shadow` shows one teapot silhouette and no
  ///   ground, because a single-sided floor is culled by [casterFaces].
  /// * *Second-depth recording defeats it* — PCSS wants the distance to the
  ///   near side of a blocker and [ShadowCasterFaces.back] records the far one,
  ///   which would shrink `receiver - blocker` for any thick body. Plausible,
  ///   and false: switching to [ShadowCasterFaces.front] moves 99 pixels
  ///   against the fixed kernel, the same as before.
  ///
  /// * *The ceiling pins it* — [pointMaxSoftness] clamps the estimate, so two
  ///   light radii could both be resting on the same maximum. Also false:
  ///   raising the ceiling from 16 to 64 texels moves 102 pixels.
  ///
  /// [RenderSettings.showPointShadowDebug] settled it, and the answer is that
  /// there was no collapse. Measured off the debug picture — in linear space,
  /// which is a correction in itself, since the surface buffer is linear and
  /// the composite writes sRGB — the radius spans 4 to 16 texels across the
  /// shadow, a quarter of the fragments at the floor and the rest spread above
  /// it. That is contact hardening doing its job.
  ///
  /// The premise was wrong instead. Widening the kernel in this scene moves
  /// about a hundred pixels whatever drives it: a *fixed* kernel tripled from
  /// 4 to 12 texels moves 110, contact hardening against a fixed 4 moves 96,
  /// and the ceiling raised fourfold moves 102. One early measurement said
  /// 4861 for a fixed 2.5 against 20 and every careful repeat since contradicts
  /// it; treat that number as suspect rather than as the target.
  ///
  /// `cube-shadow-gap` was then built for the one condition still missing — a
  /// caster well clear of the floor, where a penumbra has room to open — and it
  /// answers 27 pixels, less than the on-floor scene. So the premise itself was
  /// the error, and it is a matter of scale rather than of correctness: a face
  /// is 1024 texels across ninety degrees, the shadow covers a small part of
  /// the screen, and a few texels of extra blur in that map is worth about a
  /// pixel of softening on screen. Nothing was ever going to move thousands.
  ///
  /// Left off, then, because a second set of taps buys about a pixel at this
  /// map resolution — an honest cost/benefit, not a defect. It earns its place
  /// when a face covers less of the world per texel, or when the emitter is
  /// genuinely large; both are worth measuring before switching it on.
  ///
  /// This is what makes a shadow sharp where its caster meets the floor and
  /// soft a metre away, which one radius cannot be. A point light is a point
  /// only in the maths; a torch flame is about ten centimetres across, and that
  /// width is exactly what decides how fast its shadows spread.
  ///
  /// It costs a second set of taps — a search for what is blocking, before the
  /// filter that softens it — so it is a real expense rather than free realism.
  final double pointLightRadius;

  /// The widest a penumbra may get, in texels of one cube face.
  ///
  /// Two jobs: it stops a blocker close to the light from spreading a shadow
  /// across the whole room, and it sets how far the blocker search reaches,
  /// since a blocker beyond the widest allowed penumbra cannot widen anything.
  final double pointMaxSoftness;

  /// Which side of a caster the cube pass records.
  final ShadowCasterFaces casterFaces;

  final bool enabled;

  /// Edge length of **one cascade's tile**, not of the whole atlas.
  ///
  /// A thousand rather than two, and that is a reduction only on paper. The
  /// atlas is `resolution × cascades` wide, so the pairing is what matters:
  /// three tiles of a thousand cover a level far better than one tile of two
  /// thousand, and cost less doing it — see [cascades] for the arithmetic.
  ///
  /// **The cube atlas no longer reads this**, and the arithmetic of why is
  /// worth the paragraph. It used to: the same number was clamped to
  /// [minCubeTile]–[maxCubeTile] and used for a cube tile as well. A game
  /// asking for a 1024 sun therefore got a cube atlas six tiles across and
  /// `Renderer.kShadowedLights` rows down of the same size — at six rows,
  /// 6144 × 6144 texels of `r16g16b16a16Float`, **302 MB**, and there are two
  /// of them, the movers and the bake. Six hundred megabytes of video memory
  /// for shadows nobody asked to be that sharp, on a platform where the whole
  /// browser tab has less.
  ///
  /// So a cube tile is [cubeResolution] now, with its own default, and one
  /// number no longer sets a budget six times larger than the one it is named
  /// for.
  final int resolution;

  /// Edge length of **one cube face**, of which the atlas holds thirty-six.
  ///
  /// Separate from [resolution] because the two buy very different amounts of
  /// picture for the same texels. A cascade tile covers the part of a level the
  /// camera can see; a cube face covers a ninety-degree cone out to a lamp's
  /// range, which for a torch is a few metres of wall. Five hundred and twelve
  /// texels across that is about a centimetre per texel at two metres — finer
  /// than the shadow's own penumbra — while the same number for the sun would
  /// be visibly blocky.
  ///
  /// The atlas is `cubeResolution × 6` square — six faces across and
  /// `Renderer.kShadowedLights` rows down. At the default that is 3072 × 3072,
  /// or 75 MB in the HDR format, twice. Deriving the tile from [resolution]
  /// instead, as it used to, would make the same atlas 302 MB.
  final int cubeResolution;

  /// What the cascade pass will accept as a tile size.
  static const int minResolution = 256;
  static const int maxResolution = 4096;

  /// What the cube atlas will accept, which is lower for the reason in
  /// [cubeResolution]: the atlas holds thirty-six of these — six faces across,
  /// six lights down.
  static const int minCubeTile = 128;
  static const int maxCubeTile = 1024;

  /// Depth bias, in the shadow camera's normalized depth. Fights the acne that
  /// comes from a surface being sampled at a slightly different depth than it
  /// was rendered at.
  final double bias;

  /// How far along the surface normal the sample point moves before being
  /// projected, in world units. Fixes the acne a depth bias cannot, because that
  /// error scales with the surface's slope rather than with depth.
  final double normalOffset;

  /// How dark a fully shadowed fragment gets, from 0 to 1.
  final double strength;

  /// How much room to leave around the scene bounds along the light's axis, as
  /// a multiplier. A caster just outside the fitted volume would otherwise be
  /// clipped out of the map and stop casting.
  final double depthPadding;

  ShadowSettings copyWith({
    bool? enabled,
    int? resolution,
    int? cubeResolution,
    double? bias,
    double? normalOffset,
    double? strength,
    double? depthPadding,
    double? pointBias,
    double? pointNormalOffset,
    double? pointSoftness,
    double? pointLightRadius,
    double? pointMaxSoftness,
    ShadowCasterFaces? casterFaces,
    int? cascades,
    double? cascadeSplit,
    double? viewDistance,
  }) =>
      // Every field, and that is not bookkeeping. This method already dropped
      // the point-shadow settings on the floor: `settingsFrom` calls it once a
      // frame, so anything not listed here was silently reset to its default
      // and no amount of setting it would have had any effect. The same shape
      // of bug once meant a torch marked as a caster cast nothing.
      ShadowSettings(
        enabled: enabled ?? this.enabled,
        resolution: resolution ?? this.resolution,
        cubeResolution: cubeResolution ?? this.cubeResolution,
        bias: bias ?? this.bias,
        normalOffset: normalOffset ?? this.normalOffset,
        strength: strength ?? this.strength,
        depthPadding: depthPadding ?? this.depthPadding,
        pointBias: pointBias ?? this.pointBias,
        pointNormalOffset: pointNormalOffset ?? this.pointNormalOffset,
        pointSoftness: pointSoftness ?? this.pointSoftness,
        pointLightRadius: pointLightRadius ?? this.pointLightRadius,
        pointMaxSoftness: pointMaxSoftness ?? this.pointMaxSoftness,
        casterFaces: casterFaces ?? this.casterFaces,
        // The three the comment above was written about, missing for exactly
        // the reason it names: a caller who set `cascades: 3` and went through
        // `copyWith` got one cascade back and no way to tell.
        cascades: cascades ?? this.cascades,
        cascadeSplit: cascadeSplit ?? this.cascadeSplit,
        viewDistance: viewDistance ?? this.viewDistance,
      );
}
