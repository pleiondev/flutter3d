import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'light_node.dart';

/// Light type codes as the shader reads them.
///
/// Explicit integers rather than an enum index: the value is written into a
/// uniform and compared against a literal in GLSL, so a reordered enum would
/// silently re-type every light in the scene.
abstract final class ShaderLightType {
  static const double directional = 0.0;
  static const double point = 1.0;
  static const double spot = 2.0;

  static double of(LightType type) => switch (type) {
    LightType.directional => directional,
    LightType.point => point,
    LightType.spot => spot,
  };
}

/// The scene's active lights, packed the way the fragment shaders read them.
///
/// Four `vec4` arrays plus a count, because that is what a uniform block can
/// hold and what turning a light on or off must not disturb: the count is a
/// uniform, so the shader loop shortens without any pipeline being rebuilt.
/// That constraint is not a preference — with shaders compiled ahead of time
/// there is no recompilation available to fall back on.
///
/// The arrays are allocated once and refilled in place, so gathering lights
/// costs nothing per frame.
///
/// ## Eight slots, and a scene with hundreds of lights
///
/// The eight is a property of the *draw*, not of the scene: the scene may
/// register as many lights as it likes, and each draw is told about the eight
/// that matter where it stands. [gather] takes the first eight in scene order,
/// which is what a frame wants when they all fit; [gatherNear] picks the eight
/// that actually reach an object, which is what a night map with forty torches
/// wants. Both fill the same four arrays, so no shader knows the difference.
///
/// ## The layout
///
/// For light `i`:
///
/// | Array | xyz | w |
/// |---|---|---|
/// | `positions` | world position (point, spot) | type code |
/// | `colors` | linear RGB | intensity |
/// | `directions` | the direction it points, its local -Z | range, 0 for unbounded |
/// | `cones` | x: cos(inner), y: cos(outer) | unused |
final class LightBuffer {
  /// The shader declares arrays of this length, so it is a compile-time
  /// constant on both sides. Raising it means rebuilding the bundle.
  static const int maxLights = 8;

  final Float32List positions = Float32List(maxLights * 4);
  final Float32List colors = Float32List(maxLights * 4);
  final Float32List directions = Float32List(maxLights * 4);
  final Float32List cones = Float32List(maxLights * 4);

  /// The nodes behind the packed slots, in slot order.
  ///
  /// Needed because a shadow belongs to a light, and the shader knows lights
  /// only by their index here. Without this the renderer can build a shadow
  /// map and then be unable to say which light it is for.
  final List<LightNode> packed = <LightNode>[];

  int _count = 0;
  int _overflow = 0;

  /// Lights actually packed, never more than [maxLights].
  int get count => _count;

  /// Lights that did not fit, so a caller can say so rather than leave the user
  /// wondering why the ninth lamp does nothing.
  ///
  /// After [gatherNear] it is the same arithmetic read against one object: how
  /// many of the scene's live lights this draw was not told about.
  int get overflow => _overflow;

  final Vector3 _direction = Vector3.zero();
  final Vector3 _position = Vector3.zero();

  /// The scene's live lights, in scene order, as [collect] last found them.
  final List<LightNode> candidates = <LightNode>[];

  /// What ranking a candidate needs, read once instead of once per object.
  ///
  /// Walking the node hierarchy for a world position is the expensive half of
  /// scoring, and with hundreds of lights against thousands of objects it would
  /// be paid a million times a frame. For candidate `i`, starting at
  /// `i * _kCandidateStride`:
  ///
  /// | Offset | Holds |
  /// |---|---|
  /// | 0..2 | world position |
  /// | 3 | range, 0 for unbounded |
  /// | 4 | intensity |
  /// | 5 | 1 for a directional light, 0 for one with a position |
  Float32List _candidateData = Float32List(_kCandidateStride * maxLights);

  static const int _kCandidateStride = 6;

  /// Which candidates the current pack chose, and how strongly each scored.
  ///
  /// Hot-loop scratch: [gatherNear] runs once per draw, and a fresh pair of
  /// eight-element lists per draw is exactly the allocation the render list
  /// exists to avoid.
  final Int32List _chosen = Int32List(maxLights);
  final Float64List _chosenScore = Float64List(maxLights);

  /// Reads every live light of [lights] into the candidate table.
  ///
  /// Live means visible in its hierarchy and switched on; a light failing
  /// either is not a light that lost a slot, it is a light that is not there,
  /// and counting it in [overflow] would report a scene as crowded because
  /// somebody turned a lamp off.
  /// Whether any candidate asks for a channel — `gfx-12n`.
  ///
  /// Read by the per-draw selection to keep the fast path exactly as fast as
  /// it was: a scene with no channels takes the same short-circuit and packs
  /// the same bytes, and that is what "zero changes to frames with no
  /// channels" means as something a test can check rather than a hope.
  bool get anyChannelled => _anyChannelled;
  bool _anyChannelled = false;

  /// Whether [channels] admits [light].
  static bool reaches(LightNode light, int channels) =>
      light.channels & channels != 0;

  void collect(List<LightNode> lights) {
    candidates.clear();
    _anyChannelled = false;
    for (var i = 0; i < lights.length; i++) {
      final light = lights[i];
      if (!light.visibleInHierarchy) continue;
      if (light.intensity <= 0.0) continue;
      candidates.add(light);
      if (light.channels != LightChannels.all) _anyChannelled = true;
    }

    final needed = candidates.length * _kCandidateStride;
    // Grown to fit and never shrunk: a scene's light count settles within a
    // frame or two, and a table that shrinks reallocates every time a torch
    // goes out.
    if (_candidateData.length < needed) _candidateData = Float32List(needed);

    for (var i = 0; i < candidates.length; i++) {
      final light = candidates[i];
      light.readWorldPosition(_position);
      final at = i * _kCandidateStride;
      _candidateData[at] = _position.x;
      _candidateData[at + 1] = _position.y;
      _candidateData[at + 2] = _position.z;
      _candidateData[at + 3] = math.max(light.range, 0.0);
      _candidateData[at + 4] = light.intensity;
      _candidateData[at + 5] = light.type == LightType.directional ? 1.0 : 0.0;
    }
  }

  /// Packs the live lights of [lights] into the arrays, in scene order.
  ///
  /// What a frame wants: eight slots handed out first come, first served, so a
  /// scene that fits is packed in the order it was written down and every draw
  /// in the frame sees the same eight. When the scene does not fit, this is
  /// still the right answer for the frame *as a whole* — the shadow atlas is
  /// assigned against it, and a frame-wide table cannot be per object — but it
  /// is the wrong answer for any individual draw, and [gatherNear] is how a
  /// draw asks again.
  void gather(List<LightNode> lights) {
    collect(lights);
    _reset();
    for (var i = 0; i < candidates.length && _count < maxLights; i++) {
      _pack(candidates[i]);
    }
    _overflow = candidates.length - _count;
  }

  /// Packs the [maxLights] most relevant lights for an object whose bounding
  /// sphere is [centre] with [radius], scoring against [table]'s candidates.
  ///
  /// ## What relevance means
  ///
  /// The radiance the fragment shader will compute, and nothing invented
  /// beside it: intensity times the glTF punctual attenuation of `surface.glsl`
  /// — inverse square, windowed by the declared range — measured to the nearest
  /// point of the object's bounding sphere rather than to its centre. The
  /// nearest point is what matters: a floor tile a hundred metres across has
  /// its centre far from every torch and its surface right beside one.
  ///
  /// Ranking by the shader's own term rather than by a proxy is the whole
  /// argument for the metric. A proxy — nearest centre, brightest, largest
  /// solid angle — is a second opinion about lighting that the shader never
  /// hears, and the two drift apart exactly where they matter, at the edge of
  /// a range window. This one cannot drift: a light this drops is a light whose
  /// contribution the shader would have computed as smaller than one it kept.
  ///
  /// A directional light is not ranked. It has no position, so "nearest" says
  /// nothing about it, and it is the light a scene is lit *by* rather than one
  /// it is decorated with; dropping the sun because a torch is close would be
  /// the one selection artefact everybody would see. Directionals take slots
  /// first, in scene order, and the ranking spends what is left.
  ///
  /// A spot is scored as though it lit the whole sphere its range describes.
  /// Testing a cone against a sphere costs an inverse trigonometric call per
  /// light per object, and the error it saves runs the safe way: an over-rated
  /// spot spends a slot, while an under-rated one leaves a surface dark that
  /// the shader was ready to light.
  ///
  /// ## Why ties break on scene order
  ///
  /// Two lamps either side of a corridor score identically, and something has
  /// to choose. Scene order is the cheapest honest rule and, more to the point,
  /// the only stable one: a tie broken by anything the frame carries — a hash,
  /// an iteration order, the previous frame's answer — swaps the two lamps
  /// between frames, which is a flicker on screen and a golden that will not
  /// reproduce.
  ///
  /// The chosen eight are then packed *in scene order* as well, rather than
  /// strongest first. Two reasons: a scene that fits packs identically through
  /// either method, so nothing that fits can change appearance by adopting
  /// this; and a light that stays chosen keeps its slot while the set holds,
  /// which keeps the shadow slot table from churning as the camera walks.
  ///
  /// ## The pop at the edge of the list, and [fadeBand] — `gfx-05n`
  ///
  /// Ranking correctly does not stop a light from *arriving*. Walk a camera
  /// down a corridor of forty torches and the eighth slot changes hands every
  /// few metres; the light leaving was contributing whatever the ranking said
  /// it was, and the next frame it contributes nothing. That is the pop, and
  /// it is a property of any hard cut-off, however good the ranking is.
  ///
  /// [fadeBand] closes it by making the edge of the list a ramp rather than a
  /// cliff. The strongest score this selection *rejected* is the water line:
  /// a light exactly at it contributes nothing, one at `(1 + fadeBand)` times
  /// it contributes fully, and in between its intensity is scaled smoothly.
  /// Two lights swapping places are then both near the water line, both near
  /// nothing, and the swap has nothing to show.
  ///
  /// **Nought, the default, is the old hard edge exactly** — not approximately:
  /// with no band there is nothing to divide by and every chosen light packs
  /// its own intensity, byte for byte. That is what lets this ship without
  /// moving a recorded frame on a backend this machine cannot re-record.
  ///
  /// **A scene that fits pays nothing either way.** The water line is the best
  /// *rejected* score, and a selection that rejected nothing has none — so a
  /// scene inside [maxLights] fades nothing even with a band set, which is the
  /// same "only overflow pays" rule the rest of this method follows.
  void gatherNearFrom(
    LightBuffer table,
    Vector3 centre,
    double radius, {
    int channels = LightChannels.all,
    double fadeBand = 0.0,
  }) {
    _reset();

    // Read out of the vector once. Every component read inside the loop is a
    // getter over a Float64List, and the loop runs once per light per object.
    final cx = centre.x;
    final cy = centre.y;
    final cz = centre.z;
    final data = table._candidateData;

    var chosen = 0;
    var weakest = 0;
    // The strongest score this selection turned away — the water line the
    // fade is measured against. Stays nought when nothing was turned away.
    var rejected = 0.0;
    final length = table.candidates.length;
    for (var i = 0; i < length; i++) {
      // Channels before relevance — `gfx-12n`. A light this object is not on
      // the channel of should not take one of its eight slots, which is the
      // difference between a channel and a check made in the shader.
      if (channels != LightChannels.all &&
          !reaches(table.candidates[i], channels)) {
        continue;
      }
      final score = _relevanceIn(data, i, cx, cy, cz, radius);
      // Zero is not a weak light, it is a light this object is outside of.
      // Packing it would spend a slot on a term the shader evaluates to black.
      if (score <= 0.0) continue;

      if (chosen < maxLights) {
        _chosen[chosen] = i;
        _chosenScore[chosen] = score;
        chosen++;
        if (chosen == maxLights) weakest = _weakest(chosen);
        continue;
      }

      // Strictly better, so an incumbent survives an equal score and the
      // earlier light wins the tie.
      if (score <= _chosenScore[weakest]) {
        if (score > rejected) rejected = score;
        continue;
      }
      final evicted = _chosenScore[weakest];
      if (evicted > rejected) rejected = evicted;
      _chosen[weakest] = i;
      _chosenScore[weakest] = score;
      weakest = _weakest(chosen);
    }

    // Insertion sort back into scene order. Eight elements at most, and almost
    // always already sorted, so this is a handful of compares.
    for (var i = 1; i < chosen; i++) {
      final value = _chosen[i];
      final score = _chosenScore[i];
      var j = i - 1;
      while (j >= 0 && _chosen[j] > value) {
        _chosen[j + 1] = _chosen[j];
        _chosenScore[j + 1] = _chosenScore[j];
        j--;
      }
      _chosen[j + 1] = value;
      _chosenScore[j + 1] = score;
    }

    // Above the top of the band nothing is scaled, so the whole fade costs a
    // comparison in the ordinary case: one full light at the water line is
    // rare, and eight of them is a corridor of identical torches.
    final ceiling = rejected * (1.0 + fadeBand);
    final fading = fadeBand > 0.0 && rejected > 0.0;
    for (var i = 0; i < chosen; i++) {
      _pack(
        table.candidates[_chosen[i]],
        scale: fading ? _edgeFade(_chosenScore[i], rejected, ceiling) : 1.0,
      );
    }
    _overflow = table.candidates.length - _count;
  }

  /// How much of a chosen light survives its distance from the water line.
  ///
  /// Smoothstep rather than a straight ramp: the derivative is nought at both
  /// ends, so a light does not start fading with a visible kink the moment it
  /// crosses the top of the band — which would be a second, smaller pop in
  /// place of the one this removes.
  ///
  /// [score] is infinite for a directional light, which falls out correctly
  /// without a branch: `infinity > ceiling`, so the sun is never faded.
  static double _edgeFade(double score, double floor, double ceiling) {
    if (score >= ceiling) return 1.0;
    if (score <= floor) return 0.0;
    final t = (score - floor) / (ceiling - floor);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Packs whichever of [table]'s candidates [channels] admits, in order —
  /// `gfx-12n`'s path for a scene that fits in [maxLights].
  ///
  /// **Separate from [gatherNearFrom] because relevance is not the question
  /// here.** A scene inside eight lights packs them all and ranks nothing; a
  /// channel does not make it overflow, it makes it *smaller*. Sending it
  /// through the ranking path would compute a score per light to answer a
  /// question nobody asked, and would drop a light whose attenuation is zero
  /// at this object — which the unranked path deliberately keeps, so that a
  /// scene inside eight sees the same eight everywhere.
  void gatherMatchingFrom(LightBuffer table, int channels) {
    _reset();
    for (var i = 0; i < table.candidates.length && _count < maxLights; i++) {
      final light = table.candidates[i];
      if (!reaches(light, channels)) continue;
      _pack(light);
    }
    // Nothing is left waiting: what a channel excluded is not overflow, it is
    // a light that does not apply, and reporting it as pressure on the eight
    // slots would read as a scene that needs selection when it does not.
    _overflow = 0;
  }

  /// [gatherNearFrom] against this buffer's own candidates.
  ///
  /// For a caller that gathers and selects with one buffer — a test, or a scene
  /// drawn on its own. A frame uses the two-buffer form: its own buffer holds
  /// the table and the packing the shadow atlas was assigned against, and a
  /// second buffer is repacked per draw without disturbing it.
  void gatherNear(Vector3 centre, double radius, {double fadeBand = 0.0}) =>
      gatherNearFrom(this, centre, radius, fadeBand: fadeBand);

  /// Which of the chosen slots is the easiest to give up.
  ///
  /// Ties go to the later light in scene order, so that evicting the weakest
  /// keeps the earlier of two equals — the same rule the score comparison
  /// applies, stated for the other side of the exchange.
  int _weakest(int chosen) {
    var worst = 0;
    for (var i = 1; i < chosen; i++) {
      if (_chosenScore[i] < _chosenScore[worst] ||
          (_chosenScore[i] == _chosenScore[worst] &&
              _chosen[i] > _chosen[worst])) {
        worst = i;
      }
    }
    return worst;
  }

  /// How much candidate [index] of [data] contributes to a sphere at
  /// `(cx, cy, cz)` with [radius].
  ///
  /// Infinite for a directional light, which is how "not ranked" is spelled in
  /// a single comparison: nothing outscores it and nothing evicts it.
  ///
  /// Static, over loose doubles and the raw table, and written in plain
  /// arithmetic rather than through `math.max` and `clamp`. That is not style,
  /// it is the measurement: this runs once per light per object — two hundred
  /// thousand times a frame at a thousand objects and two hundred lamps — and
  /// `clamp` on a `double` is declared to return `num`, so every call boxed.
  /// Spelling the comparisons out, reading the centre out of its vector once,
  /// and rejecting an out-of-range lamp before the square root took that frame
  /// from 16.8 ms to 5.0 in the test VM, where an empty loop of the same two
  /// hundred thousand iterations already costs 2.4.
  static double _relevanceIn(
    Float32List data,
    int index,
    double cx,
    double cy,
    double cz,
    double radius,
  ) {
    final at = index * _kCandidateStride;
    if (data[at + 5] != 0.0) return double.infinity;

    final dx = data[at] - cx;
    final dy = data[at + 1] - cy;
    final dz = data[at + 2] - cz;
    final squared = dx * dx + dy * dy + dz * dz;

    final range = data[at + 3];
    if (range > 0.0) {
      // Out of reach, answered without a square root. This is what makes
      // hundreds of lamps affordable: a lamp declares a range, an object is
      // almost never inside it, and the rejection is three multiplies and a
      // comparison.
      final reach = range + radius;
      if (squared > reach * reach) return 0.0;
    }

    // To the surface of the object, not its centre, and never negative: a
    // light inside the bounds is at distance zero and scores its ceiling.
    final surface = math.sqrt(squared) - radius;
    final distance = surface > 0.0 ? surface : 0.0;

    // `PunctualAttenuation` from surface.glsl, restated. The two must agree,
    // and the way to keep them agreeing is that this is a transcription rather
    // than an approximation.
    final falloff = distance * distance;
    var attenuation = 1.0 / (falloff > 1e-4 ? falloff : 1e-4);
    if (range > 0.0) {
      final ratio = distance / range;
      final quartic = ratio * ratio * ratio * ratio;
      final window = quartic < 1.0 ? 1.0 - quartic : 0.0;
      attenuation *= window * window;
    }
    return data[at + 4] * attenuation;
  }

  void _reset() {
    _count = 0;
    _overflow = 0;
    packed.clear();
  }

  /// Writes one light into the next free slot, its intensity scaled by
  /// [scale] — nought to one, and one for every caller but the edge fade.
  ///
  /// The intensity and not the colour, because they are the same multiply to
  /// the shader and only one of them is a number nobody authored: dimming a
  /// light by writing a darker colour would show up in a debug view as a lamp
  /// somebody tinted.
  void _pack(LightNode light, {double scale = 1.0}) {
    packed.add(light);
    final slot = _count * 4;
    light.readDirection(_direction);
    light.readWorldPosition(_position);

    positions[slot] = _position.x;
    positions[slot + 1] = _position.y;
    positions[slot + 2] = _position.z;
    positions[slot + 3] = ShaderLightType.of(light.type);

    colors[slot] = light.color.x;
    colors[slot + 1] = light.color.y;
    colors[slot + 2] = light.color.z;
    colors[slot + 3] = light.intensity * scale;

    directions[slot] = _direction.x;
    directions[slot + 1] = _direction.y;
    directions[slot + 2] = _direction.z;
    directions[slot + 3] = math.max(light.range, 0.0);

    // Cosines rather than angles: the shader compares against a dot product,
    // and doing the conversion here keeps a transcendental out of the inner
    // loop of every fragment.
    //
    // The inner cone is clamped just inside the outer one. glTF allows them
    // to be equal, which makes the falloff divide by zero, and the result is
    // a spot light that renders as a black disc.
    final outer = light.outerConeAngle.clamp(0.0, math.pi / 2.0);
    final inner = light.innerConeAngle.clamp(0.0, outer);
    final cosOuter = math.cos(outer);
    var cosInner = math.cos(inner);
    if (cosInner - cosOuter < 1e-4) cosInner = cosOuter + 1e-4;

    cones[slot] = cosInner;
    cones[slot + 1] = cosOuter;
    cones[slot + 2] = 0.0;
    cones[slot + 3] = 0.0;

    _count++;
  }

  /// Fills slot zero with a neutral key light.
  ///
  /// A scene with no lights at all would otherwise render as pure ambient,
  /// which reads as "the renderer is broken" rather than "you forgot a light".
  void useDefaultLight() {
    // [packed] is what the shadow slot table is rebuilt from, and this light
    // has no node behind it. Cleared rather than left, so a stale entry cannot
    // hand slot zero the atlas row of a light that is no longer in the buffer.
    packed.clear();
    _count = 1;
    _overflow = 0;

    final direction = Vector3(-0.45, -0.8, -0.6)..normalize();

    positions[0] = 0.0;
    positions[1] = 0.0;
    positions[2] = 0.0;
    positions[3] = ShaderLightType.directional;

    colors[0] = 1.0;
    colors[1] = 0.97;
    colors[2] = 0.92;
    colors[3] = 1.0;

    directions[0] = direction.x;
    directions[1] = direction.y;
    directions[2] = direction.z;
    directions[3] = 0.0;

    cones[0] = 1.0;
    cones[1] = 0.0;
    cones[2] = 0.0;
    cones[3] = 0.0;
  }

  @override
  String toString() =>
      'LightBuffer($_count lights'
      '${_overflow > 0 ? ', $_overflow dropped' : ''})';
}
