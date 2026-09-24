import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'light_shading.dart';
import 'light_views.dart';

/// Fewer lights that light a level the way its author lit it.
///
/// **What it does.** Every light is drawn once from every view by
/// [LightShading], alone, in linear light. With visibility frozen — each
/// light's shadow is the one it cast when it was drawn — the picture under
/// any strengths and colours is the level's unlit picture plus each light's
/// picture scaled channel by channel, so the image loss has an exact
/// gradient in every light's strength and colour and needs no further
/// drawing to follow it. Around that differentiable core the search makes
/// the structural moves: it removes a light, or merges two into one drawn
/// where they were (the one move that draws again), retunes every light
/// left, and keeps the move when the picture is still within [maxDifference]
/// of the original and no more than [maxUnderLit] of it went dark.
///
/// **The loss** is the mean squared difference from the original picture
/// plus the two regularisers the idea came with: *under-illumination*, a
/// hinge on every pixel that falls below [darkening] of its original
/// brightness, weighted by [underWeight] inside the retune; and *redundant
/// overlap*, how much of a light's picture other lights already cover,
/// which orders the moves — the most redundant light is tried first — and
/// is reported before and after.
///
/// **Measured, then drawn.** The numbers a [LightPlan] reports for the new
/// set come from drawing it, not from the sum the search worked with, so a
/// merged light whose shadow fell differently from its parents' is judged
/// by the shadow it actually casts.
final class LightOptimizer {
  const LightOptimizer({
    this.maxDifference = 0.01,
    this.maxUnderLit = 0.01,
    this.darkening = 0.75,
    this.underWeight = 4.0,
    this.sweeps = 60,
    this.maxMerges = 16,
    this.width = 160,
    this.height = 100,
  });

  /// The largest mean difference from the original picture a move may leave,
  /// per channel in display values from nought to one — `0.01` is about two
  /// and a half steps of an 8-bit channel.
  final double maxDifference;

  /// The largest share of the pictures' lit pixels a move may leave darker
  /// than [darkening] of what they were.
  final double maxUnderLit;

  /// How dark a pixel may get, as a share of its original brightness, before
  /// it counts as under-lit.
  final double darkening;

  /// How much the under-illumination hinge weighs in the retune, against the
  /// squared difference.
  final double underWeight;

  /// How many passes over every strength and colour a retune may take.
  final int sweeps;

  /// How many merges may be drawn and tried in one optimisation — the only
  /// moves that cost a render per view.
  final int maxMerges;

  /// The size each view is drawn at. Small, because the pictures are for
  /// deciding and the decision does not need the detail.
  final int width;
  final int height;

  /// Optimises [level]'s lights as seen from [views], under every one of
  /// [states] at once.
  ///
  /// [level] is not changed: the answer is a [LightPlan] whose
  /// [LightPlan.after] a caller writes into the document as one edit.
  LightPlan optimize(
    Level level, {
    required List<LightView> views,
    List<LightingState> states = const <LightingState>[LightingState.asIs],
  }) {
    if (views.isEmpty) {
      throw ArgumentError.value(views, 'views', 'no view to judge lights from');
    }
    if (states.isEmpty) {
      throw ArgumentError.value(states, 'states', 'no lighting state');
    }
    final shading = LightShading.of(level, width: width, height: height);
    final perView = shading.pixels;
    final frames = <({LightView view, LightingState state})>[
      for (final state in states)
        for (final view in views) (view: view, state: state),
    ];
    final total = frames.length * perView;

    // The unlit picture of every frame — its state's own lights and nothing
    // of the level's — and what each level light adds to it: the light
    // drawn alone less the level with no light at all, once per view and
    // shared by every state, since what a light adds does not depend on
    // what else is lit.
    final unlitByView = <LightView, Float32List>{};
    Float32List stacked(Float32List Function(LightView view) draw) {
      final byView = <LightView, Float32List>{};
      final out = Float32List(total * 3);
      for (var f = 0; f < frames.length; f++) {
        final view = frames[f].view;
        final picture = byView[view] ??= () {
          final lit = draw(view);
          final unlit = unlitByView[view] ??= shading.render(view, const []);
          for (var i = 0; i < lit.length; i++) {
            lit[i] -= unlit[i];
          }
          return lit;
        }();
        out.setAll(f * perView * 3, picture);
      }
      return out;
    }

    final base = Float32List(total * 3);
    for (var f = 0; f < frames.length; f++) {
      base.setAll(
        f * perView * 3,
        shading.render(frames[f].view, frames[f].state.lights),
      );
    }
    final original = level.lights.toList();
    final candidates = <_Light>[
      for (var i = 0; i < original.length; i++)
        _Light(
          original[i],
          stacked((view) => shading.render(view, <LevelLight>[original[i]])),
          from: <int>[i],
        ),
    ];

    final reference = Float32List.fromList(base);
    for (final light in candidates) {
      _addInto(reference, light.picture, Vector3.all(1.0));
    }
    final problem = _Problem(
      base: base,
      reference: reference,
      darkening: darkening,
      underWeight: underWeight,
    );

    var set = <_Tuned>[
      for (final light in candidates) _Tuned(light, Vector3.all(1.0)),
    ];
    final moves = <String>[];
    var mergesLeft = maxMerges;

    bool fits(_Fit fit) =>
        fit.difference <= maxDifference && fit.underLit <= maxUnderLit;

    // One accepted move per round; a round with none ends the search. Down
    // to no level light at all, which a state's own lights can make right:
    // the lamp a noon sun drowns out.
    while (set.isNotEmpty) {
      final overlap = problem.overlaps(set);
      final order = List<int>.generate(set.length, (i) => i)
        ..sort((a, b) {
          final byOverlap = overlap[b].compareTo(overlap[a]);
          return byOverlap != 0 ? byOverlap : a.compareTo(b);
        });

      ({List<_Tuned> set, String says})? accepted;
      for (final i in order) {
        final trial = problem.retune(<_Tuned>[
          for (var j = 0; j < set.length; j++)
            if (j != i) set[j].copy(),
        ], sweeps);
        if (fits(problem.fit(trial))) {
          accepted = (set: trial, says: 'removed ${set[i].light.label}');
          break;
        }
      }
      if (accepted == null) {
        for (final (i, j) in _mergeable(set, overlap)) {
          if (mergesLeft <= 0) break;
          mergesLeft--;
          final merged = _merge(set[i], set[j]);
          final light = _Light(
            merged,
            stacked((view) => shading.render(view, <LevelLight>[merged])),
            from: <int>[...set[i].light.from, ...set[j].light.from],
          );
          final trial = problem.retune(<_Tuned>[
            for (var k = 0; k < set.length; k++)
              if (k == i)
                _Tuned(light, Vector3.all(1.0))
              else if (k != j)
                set[k].copy(),
          ], sweeps);
          if (fits(problem.fit(trial))) {
            accepted = (
              set: trial,
              says:
                  'merged ${set[i].light.label} and ${set[j].light.label} '
                  'into one',
            );
            break;
          }
        }
      }
      if (accepted == null) break;
      set = accepted.set;
      moves.add(accepted.says);
    }
    // A light the retune turned all the way down is a light removed.
    final retuned = problem.retune(set, sweeps);
    bool dark(_Tuned it) =>
        it.gain.x <= 0.0 && it.gain.y <= 0.0 && it.gain.z <= 0.0;
    moves.addAll(<String>[
      for (final tuned in retuned)
        if (dark(tuned)) 'removed ${tuned.light.label}',
    ]);
    set = <_Tuned>[
      for (final tuned in retuned)
        if (!dark(tuned)) tuned,
    ];

    final after = <LevelLight>[for (final tuned in set) tuned.result];
    if (set.any((it) => (it.gain - Vector3.all(1.0)).length > 1e-3)) {
      moves.add('retuned the strengths');
    }

    // The new set drawn for real, frame by frame, rather than trusted.
    final drawn = Float32List(total * 3);
    for (var f = 0; f < frames.length; f++) {
      drawn.setAll(
        f * perView * 3,
        shading.render(frames[f].view, <LevelLight>[
          ...frames[f].state.lights,
          ...after,
        ]),
      );
    }
    final fit = problem.measure(drawn);
    final exposure = _exposure;
    Uint8List display(Float32List linear) {
      final out = Uint8List(perView * 4);
      for (var p = 0; p < perView; p++) {
        for (var c = 0; c < 3; c++) {
          out[p * 4 + c] =
              (LightShading.displayOf(linear[p * 3 + c], exposure: exposure) *
                      255.0)
                  .round();
        }
        out[p * 4 + 3] = 255;
      }
      return out;
    }

    return LightPlan(
      before: original,
      after: after,
      moves: moves,
      costBefore: <double>[
        for (final light in candidates)
          problem.cost(light.picture, light.level),
      ].fold(0.0, (a, b) => a + b),
      costAfter: <double>[
        for (final tuned in set) problem.cost(tuned.scaled, tuned.result),
      ].fold(0.0, (a, b) => a + b),
      overlapBefore: problem.totalOverlap(<_Tuned>[
        for (final light in candidates) _Tuned(light, Vector3.all(1.0)),
      ]),
      overlapAfter: problem.totalOverlap(set),
      difference: fit.difference,
      underLit: fit.underLit,
      width: width,
      height: height,
      previewBefore: display(
        Float32List.sublistView(reference, 0, perView * 3),
      ),
      previewAfter: display(Float32List.sublistView(drawn, 0, perView * 3)),
    );
  }

  /// The pairs worth merging, most overlapped first: two point lights, or
  /// two spots aimed nearly the same way, each inside half the other's
  /// reach. A merge is drawn before it is judged, so this list is kept to the
  /// pairs where one light standing for both is plausible.
  static List<(int, int)> _mergeable(List<_Tuned> set, List<double> overlap) {
    bool near(LevelLight a, LevelLight b) {
      final reach = math.min(
        a.range > 0.0 ? a.range : double.infinity,
        b.range > 0.0 ? b.range : double.infinity,
      );
      final limit = reach.isFinite ? reach * 0.5 : 2.0;
      return a.position.distanceTo(b.position) <= limit;
    }

    final pairs =
        <(int, int)>[
          for (var i = 0; i < set.length; i++)
            for (var j = i + 1; j < set.length; j++)
              if (_sameKind(set[i].result, set[j].result) &&
                  near(set[i].result, set[j].result))
                (i, j),
        ]..sort((p, q) {
          final a = overlap[p.$1] + overlap[p.$2];
          final b = overlap[q.$1] + overlap[q.$2];
          return b.compareTo(a);
        });
    return pairs;
  }

  static bool _sameKind(LevelLight a, LevelLight b) =>
      a.type == b.type &&
      switch (a.type) {
        LevelLightType.point => true,
        LevelLightType.spot =>
          a.direction.normalized().dot(b.direction.normalized()) >= 0.9,
        LevelLightType.directional => false,
      };

  /// One light where two were: at the middle of their strengths, as strong
  /// as both, reaching as far as either did, and casting a shadow if either
  /// cast one. Everything else the first carried is kept.
  static LevelLight _merge(_Tuned a, _Tuned b) {
    final first = a.result;
    final second = b.result;
    final ea = _energy(first);
    final eb = _energy(second);
    final weight = ea + eb <= 0.0 ? 0.5 : eb / (ea + eb);
    final at = first.position + (second.position - first.position) * weight;
    final radiance =
        first.color * first.intensity + second.color * second.intensity;
    final reach = first.range <= 0.0 || second.range <= 0.0
        ? 0.0
        : math.max(
            first.range + first.position.distanceTo(at),
            second.range + second.position.distanceTo(at),
          );
    final direction =
        (first.direction.normalized() + second.direction.normalized())
          ..normalize();
    return _withRadiance(
      first,
      radiance,
      extra: <String, Object?>{
        'at': _tidied(at),
        'range': _tidy(reach),
        if (first.type == LevelLightType.spot) 'direction': _tidied(direction),
        if (first.castsShadow || second.castsShadow) 'castsShadow': true,
      },
    );
  }

  static double _energy(LevelLight light) =>
      light.intensity *
      math.max(light.color.x, math.max(light.color.y, light.color.z));

  /// The exposure the previews and the difference are judged at: the one a
  /// frame gets when nothing says otherwise.
  static const double _exposure = 1.6;
}

/// One set of lights the level is also seen under, besides its own — the
/// sun at noon, the sun at dusk, nothing at all at night.
///
/// A light set optimised against several states is one that still lights
/// the level the way it did under each of them: a torch the noon sun makes
/// redundant is still wanted at night.
final class LightingState {
  const LightingState(this.name, {this.lights = const <LevelLight>[]});

  /// The level's own lights and nothing more.
  static const LightingState asIs = LightingState('as is');

  final String name;

  /// Drawn in every view of this state, and never changed by the optimizer.
  final List<LevelLight> lights;
}

/// What [LightOptimizer.optimize] found: the lights before and after, what
/// it did to get there, and the numbers that say whether to take it.
final class LightPlan {
  const LightPlan({
    required this.before,
    required this.after,
    required this.moves,
    required this.costBefore,
    required this.costAfter,
    required this.overlapBefore,
    required this.overlapAfter,
    required this.difference,
    required this.underLit,
    required this.width,
    required this.height,
    required this.previewBefore,
    required this.previewAfter,
  });

  final List<LevelLight> before;
  final List<LevelLight> after;

  /// The moves kept, in order, as sentences.
  final List<String> moves;

  /// What the lights cost to shade, summed over every view: the pixels each
  /// light reaches, a shadowed light counted once more per shadow view it
  /// renders (six for a point light, one otherwise). A stand-in for a
  /// measured cost per light until there is a table of one.
  final double costBefore;
  final double costAfter;

  /// How much of the lights' pictures other lights already cover, as a share
  /// of all their light — the redundancy the optimizer removes.
  final double overlapBefore;
  final double overlapAfter;

  /// The mean difference between the original pictures and the new set's,
  /// drawn, per channel in display values from nought to one.
  final double difference;

  /// The share of lit pixels the new set leaves darker than the optimizer's
  /// `darkening` of what they were.
  final double underLit;

  /// The size of the two previews, which are RGBA bytes of the first view.
  final int width;
  final int height;
  final Uint8List previewBefore;
  final Uint8List previewAfter;

  /// Whether anything would change.
  bool get changes => moves.isNotEmpty;

  /// The two previews as PNG files.
  ({Uint8List before, Uint8List after}) get pngs => (
    before: encodePng(previewBefore, width, height),
    after: encodePng(previewAfter, width, height),
  );

  /// The numbers in one sentence.
  String get says {
    String share(double it) => '${(it * 100).toStringAsFixed(1)}%';
    final saved = costBefore <= 0.0 ? 0.0 : 1.0 - costAfter / costBefore;
    return '${before.length} → ${after.length} lights, shading cost '
        '${share(saved)} lower, difference ${difference.toStringAsFixed(4)}, '
        '${share(underLit)} of pixels darker, overlap '
        '${share(overlapBefore)} → ${share(overlapAfter)}';
  }
}

/// A light the search can use: the document's light, its picture alone from
/// every frame at the strength it was drawn with, and which of the original
/// lights it stands for.
final class _Light {
  _Light(this.level, this.picture, {required this.from});

  final LevelLight level;
  final Float32List picture;
  final List<int> from;

  String get label {
    final named = level.name;
    final which = from.length == 1
        ? 'light ${from.single}'
        : 'lights ${from.join('+')}';
    return named == null ? which : '$which ($named)';
  }
}

/// A light in a set, with the gain per channel the retune has given it.
final class _Tuned {
  _Tuned(this.light, this.gain);

  final _Light light;
  final Vector3 gain;

  _Tuned copy() => _Tuned(light, gain.clone());

  /// Its picture at its gain.
  Float32List get scaled {
    final out = Float32List(light.picture.length);
    _addInto(out, light.picture, gain);
    return out;
  }

  /// The document's light at its gain: the colour and strength scaled
  /// channel by channel, the strength taking the largest gain so an even
  /// gain leaves the colour as the author wrote it.
  LevelLight get result {
    final source = light.level;
    return _withRadiance(
      source,
      Vector3(
        source.color.x * gain.x,
        source.color.y * gain.y,
        source.color.z * gain.z,
      )..scale(source.intensity),
    );
  }
}

/// [source] with [radiance] as its colour times its strength, and [extra]
/// fields written over it — everything else it carried kept, the way
/// `Editing.brighten` keeps it.
LevelLight _withRadiance(
  LevelLight source,
  Vector3 radiance, {
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  final peak = math.max(radiance.x, math.max(radiance.y, radiance.z));
  final Vector3 colour;
  final double intensity;
  final sourcePeak = math.max(
    source.color.x,
    math.max(source.color.y, source.color.z),
  );
  // The author's colour, when the new radiance is that colour scaled: the
  // strength moves and the colour stays as written.
  final even =
      sourcePeak > 0.0 &&
      (radiance - source.color * (peak / sourcePeak)).length <=
          1e-6 * math.max(peak, 1.0);
  if (peak <= 0.0) {
    colour = source.color;
    intensity = 0.0;
  } else if (even) {
    colour = source.color;
    intensity = peak / sourcePeak;
  } else {
    colour = radiance / peak;
    intensity = peak;
  }
  return LevelLight.fromJson(<String, Object?>{
    ...source.toJson(),
    'color': _tidied(colour),
    'intensity': _tidy(intensity),
    ...extra,
  });
}

/// Three decimals, as `Editing.brighten` writes a strength: the document is
/// read in diffs, and a thousandth is below anything a picture shows.
double _tidy(double it) => double.parse(it.toStringAsFixed(3));

List<double> _tidied(Vector3 it) => <double>[
  _tidy(it.x),
  _tidy(it.y),
  _tidy(it.z),
];

void _addInto(Float32List into, Float32List picture, Vector3 gain) {
  for (var i = 0; i < into.length; i += 3) {
    into[i] += picture[i] * gain.x;
    into[i + 1] += picture[i + 1] * gain.y;
    into[i + 2] += picture[i + 2] * gain.z;
  }
}

/// How well a set matches the original pictures.
typedef _Fit = ({double difference, double underLit});

/// The pictures a search works against, and the arithmetic on them.
final class _Problem {
  _Problem({
    required this.base,
    required this.reference,
    required this.darkening,
    required this.underWeight,
  }) : pixels = base.length ~/ 3,
       _referenceLuma = Float64List(base.length ~/ 3) {
    var sum = 0.0;
    var lit = 0;
    for (var p = 0; p < pixels; p++) {
      final y = _luma(reference, p);
      _referenceLuma[p] = y;
      sum += y;
      if (y > _litFloor) lit++;
    }
    _scale = math.max(sum / pixels, 1e-6);
    _lit = math.max(lit, 1);
  }

  final Float32List base;
  final Float32List reference;
  final double darkening;
  final double underWeight;
  final int pixels;
  final Float64List _referenceLuma;
  late final double _scale;
  late final int _lit;

  /// Below this, a pixel was dark in the original and cannot be made darker
  /// in any way anybody would see.
  static const double _litFloor = 1e-3;

  static const double _wr = 0.2126;
  static const double _wg = 0.7152;
  static const double _wb = 0.0722;

  static double _luma(Float32List rgb, int p) =>
      _wr * rgb[p * 3] + _wg * rgb[p * 3 + 1] + _wb * rgb[p * 3 + 2];

  Float32List _image(List<_Tuned> set) {
    final image = Float32List.fromList(base);
    for (final tuned in set) {
      _addInto(image, tuned.light.picture, tuned.gain);
    }
    return image;
  }

  /// Every gain in [set] moved to lower the loss, a coordinate at a time.
  ///
  /// **Newton steps on one strength at a time, clamped at nothing.** The
  /// squared difference is quadratic in each gain and the hinge is quadratic
  /// on each side of its knee, so a step to where the gradient in one
  /// coordinate vanishes is exact for the first and close for the second;
  /// a light cannot be negative, so a step past nought stops there.
  List<_Tuned> retune(List<_Tuned> set, int sweeps) {
    final image = _image(set);
    final luma = Float64List(pixels);
    for (var p = 0; p < pixels; p++) {
      luma[p] = _luma(image, p);
    }
    final quadratic = 2.0 / (3.0 * pixels * _scale * _scale);
    final hinge = underWeight * 2.0 / (pixels * _scale * _scale);
    const weights = <double>[_wr, _wg, _wb];
    for (var sweep = 0; sweep < sweeps; sweep++) {
      var moved = 0.0;
      for (final tuned in set) {
        final picture = tuned.light.picture;
        for (var c = 0; c < 3; c++) {
          final w = weights[c];
          var g = 0.0;
          var h = 0.0;
          for (var p = 0; p < pixels; p++) {
            final k = picture[p * 3 + c];
            if (k == 0.0) continue;
            final i = p * 3 + c;
            g += quadratic * (image[i] - reference[i]) * k;
            h += quadratic * k * k;
            final under = darkening * _referenceLuma[p] - luma[p];
            if (under > 0.0) {
              g -= hinge * w * under * k;
              h += hinge * w * w * k * k;
            }
          }
          if (h <= 0.0) continue;
          final old = tuned.gain[c];
          final next = math.max(0.0, old - g / h);
          final delta = next - old;
          if (delta == 0.0) continue;
          tuned.gain[c] = next;
          for (var p = 0; p < pixels; p++) {
            final k = picture[p * 3 + c];
            if (k == 0.0) continue;
            image[p * 3 + c] += delta * k;
            luma[p] += w * delta * k;
          }
          moved = math.max(moved, delta.abs() / math.max(next, 1.0));
        }
      }
      if (moved < 1e-5) break;
    }
    return set;
  }

  _Fit fit(List<_Tuned> set) => measure(_image(set));

  /// How [image] differs from the original pictures.
  _Fit measure(Float32List image) {
    var difference = 0.0;
    var under = 0;
    for (var p = 0; p < pixels; p++) {
      for (var c = 0; c < 3; c++) {
        final i = p * 3 + c;
        difference +=
            (LightShading.displayOf(
                      image[i],
                      exposure: LightOptimizer._exposure,
                    ) -
                    LightShading.displayOf(
                      reference[i],
                      exposure: LightOptimizer._exposure,
                    ))
                .abs();
      }
      final was = _referenceLuma[p];
      if (was > _litFloor && _luma(image, p) < darkening * was) under++;
    }
    return (difference: difference / (pixels * 3), underLit: under / _lit);
  }

  /// For each light of [set], the share of its light that the rest of the
  /// set already puts on the same pixels.
  List<double> overlaps(List<_Tuned> set) {
    final total = Float64List(pixels);
    final own = <Float64List>[
      for (final tuned in set)
        Float64List(pixels)..setAll(0, <double>[
          for (var p = 0; p < pixels; p++)
            tuned.gain.x * _wr * tuned.light.picture[p * 3] +
                tuned.gain.y * _wg * tuned.light.picture[p * 3 + 1] +
                tuned.gain.z * _wb * tuned.light.picture[p * 3 + 2],
        ]),
    ];
    for (final mine in own) {
      for (var p = 0; p < pixels; p++) {
        total[p] += mine[p];
      }
    }
    return <double>[for (final mine in own) _overlapOf(mine, total)];
  }

  static double _overlapOf(Float64List mine, Float64List total) {
    var shared = 0.0;
    var all = 0.0;
    for (var p = 0; p < mine.length; p++) {
      shared += math.min(mine[p], total[p] - mine[p]);
      all += mine[p];
    }
    return all <= 0.0 ? 0.0 : shared / all;
  }

  /// The redundant overlap of a whole set: the light that other lights
  /// already cover, as a share of all the set's light.
  double totalOverlap(List<_Tuned> set) {
    final per = overlaps(set);
    var shared = 0.0;
    var all = 0.0;
    for (var i = 0; i < set.length; i++) {
      final energy = _energyOf(set[i]);
      shared += per[i] * energy;
      all += energy;
    }
    return all <= 0.0 ? 0.0 : shared / all;
  }

  double _energyOf(_Tuned tuned) {
    var sum = 0.0;
    for (var p = 0; p < pixels; p++) {
      sum +=
          tuned.gain.x * _wr * tuned.light.picture[p * 3] +
          tuned.gain.y * _wg * tuned.light.picture[p * 3 + 1] +
          tuned.gain.z * _wb * tuned.light.picture[p * 3 + 2];
    }
    return sum;
  }

  /// What [light] costs to shade: the pixels its [picture] reaches, times
  /// one plus the shadow views it renders.
  double cost(Float32List picture, LevelLight light) {
    var reached = 0;
    for (var p = 0; p < pixels; p++) {
      if (_luma(picture, p) > _litFloor * 0.1) reached++;
    }
    final shadowViews = !light.castsShadow
        ? 0
        : light.type == LevelLightType.point
        ? 6
        : 1;
    return reached * (1.0 + shadowViews).toDouble();
  }
}
