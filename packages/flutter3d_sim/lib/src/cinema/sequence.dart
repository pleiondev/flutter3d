/// A cutscene as a document: a camera on a path, words on the screen, a
/// fade, and signals to the game at given moments.
///
/// ## In steps, not in seconds
///
/// A document says when things happen in seconds, because that is how a
/// person writing one thinks. [Sequence.read] turns every moment into the
/// whole step it falls on, once, for the step rate it is read for; after
/// that a cutscene is compared in integers, so a signal is fired on the same
/// step on every machine a run is replayed on, and a cutscene restored from
/// a snapshot at step 300 fires what is after 300 and nothing before.
///
/// ## What a cutscene does not do
///
/// It names no sound, no clip, no animation parameter. Those are the game's,
/// and a cutscene reaches them the way a simulation reaches anything of the
/// game's: by a signal — a `SequenceSignal` event with a name and whatever
/// data the document gave it — that the game answers. What a cutscene owns
/// is what is about the picture and nothing else: where the camera is, what
/// the subtitles say, how dark the screen is.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../math/spline.dart';

/// One camera key: where the eye is, what it looks at, how wide it sees —
/// the vertical field of view in degrees, forty-five unless the document
/// says, which is the engine's own lens, so a cutscene that names none cuts
/// to it without the picture changing size.
typedef CameraKey = ({int step, Vector3 at, Vector3 look, double fovY});

/// One subtitle: shown from step [from] up to, not including, step [to].
typedef SubtitleCue = ({int from, int to, String text});

/// One fade key: how dark the screen is at a step, nought clear and one
/// black.
typedef FadeKey = ({int step, double value});

/// One signal: [name] fired, with [data], on [step].
typedef SignalCue = ({int step, String name, Map<String, Object?> data});

/// What a cutscene tells an actor to do.
///
/// **A class with constant instances, not an enum**, because the verbs a
/// cutscene has will grow — play this, pick that up — and a value added to
/// an enum breaks every exhaustive `switch` written against it. Compared by
/// identity: [values] are the only instances there are.
final class ActorCueKind {
  const ActorCueKind._(this.name);

  /// What a document calls it.
  final String name;

  /// Walk to [ActorCue.at], over the navigation mesh where there is one, and
  /// stand there.
  static const ActorCueKind goTo = ActorCueKind._('goTo');

  /// Turn to look at [ActorCue.at], standing.
  static const ActorCueKind face = ActorCueKind._('face');

  /// Stand where it is.
  static const ActorCueKind stand = ActorCueKind._('stand');

  /// Back to its own brain.
  static const ActorCueKind release = ActorCueKind._('release');

  /// Stand, and make the gesture [ActorCue.clip] once, on the cue's step —
  /// a clip the game's animation knows by that name.
  static const ActorCueKind play = ActorCueKind._('play');

  /// Every kind, in the order a refusal lists them.
  static const List<ActorCueKind> values = <ActorCueKind>[
    goTo,
    face,
    stand,
    release,
    play,
  ];

  @override
  String toString() => name;
}

/// One actor's direction from [step] until its next: who, what, and where.
typedef ActorCue = ({
  int step,
  String actor,
  ActorCueKind kind,
  Vector3? at,
  String? clip,
});

/// What [Sequence.read] made of a document: the sequence, or every problem
/// with it and where.
typedef SequenceRead = ({Sequence? sequence, List<String> problems});

/// A cutscene, its moments in steps.
final class Sequence {
  Sequence._({
    required this.steps,
    required this.stepsPerSecond,
    required this.cameraKeys,
    required this.ease,
    required this.subtitles,
    required this.fades,
    required this.signals,
    required this.actorCues,
  }) : _path = _curve(cameraKeys, (CameraKey k) => k.at),
       _looks = _curve(cameraKeys, (CameraKey k) => k.look);

  /// How long it runs, in steps.
  final int steps;

  /// The step rate its moments were read for.
  final int stepsPerSecond;

  /// The camera's keys, in step order; empty when the cutscene leaves the
  /// camera to the game.
  final List<CameraKey> cameraKeys;

  /// Whether the camera eases in and out of each key rather than keeping one
  /// speed between them.
  final bool ease;

  final List<SubtitleCue> subtitles;
  final List<FadeKey> fades;

  /// In step order, and in document order where two share a step.
  final List<SignalCue> signals;

  /// In step order, and in document order where two share a step: an
  /// actor's direction at a step is the last of its cues at or before it.
  final List<ActorCue> actorCues;

  final CatmullRom? _path;
  final CatmullRom? _looks;

  static CatmullRom? _curve(
    List<CameraKey> keys,
    Vector3 Function(CameraKey key) of,
  ) => keys.length < 2
      ? null
      : CatmullRom(<Vector3>[for (final key in keys) of(key)], closed: false);

  /// Reads [json] for a game stepping [stepsPerSecond] times a second, or
  /// refuses it with every problem and where it is.
  ///
  /// `{"seconds": 12, "camera": {"keys": [{"t", "at", "look", "fovY"}],
  /// "ease": true}, "subtitles": [{"from", "to", "text"}], "fade": [{"t",
  /// "value"}], "signals": [{"t", "name", "data"}], "actors": [{"t",
  /// "actor", "do", "at", "clip"}]}` — every part but
  /// `seconds` may be left out. A moment past the end is a problem: a
  /// cutscene that is skipped would never reach it.
  static SequenceRead read(Object? json, {required int stepsPerSecond}) {
    final problems = <String>[];
    if (json is! Map) {
      return (sequence: null, problems: <String>['a sequence is an object']);
    }
    int stepOf(double seconds) => (seconds * stepsPerSecond).round();

    double? number(Map<Object?, Object?> row, String key, String where) {
      final value = row[key];
      if (value is num) return value.toDouble();
      problems.add('$where.$key: a number, not ${value ?? 'nothing'}');
      return null;
    }

    Vector3? vector(Map<Object?, Object?> row, String key, String where) {
      final value = row[key];
      if (value is List && value.length == 3 && value.every((e) => e is num)) {
        return Vector3(
          (value[0] as num).toDouble(),
          (value[1] as num).toDouble(),
          (value[2] as num).toDouble(),
        );
      }
      problems.add('$where.$key: three numbers');
      return null;
    }

    // Each object of the list at [value] with its index in it, so that a
    // problem further down still says which row it is in.
    List<(int, Map<Object?, Object?>)> rows(Object? value, String where) {
      if (value == null) return const <(int, Map<Object?, Object?>)>[];
      if (value is! List) {
        problems.add('$where: a list');
        return const <(int, Map<Object?, Object?>)>[];
      }
      final out = <(int, Map<Object?, Object?>)>[];
      for (final (i, row) in value.indexed) {
        if (row is Map) {
          out.add((i, row));
        } else {
          problems.add('$where[$i]: an object');
        }
      }
      return out;
    }

    final seconds = number(json, 'seconds', 'sequence');
    final steps = seconds == null ? 0 : stepOf(seconds);
    if (seconds != null && steps <= 0) {
      problems.add('sequence.seconds: longer than nothing');
    }

    int? moment(Map<Object?, Object?> row, String key, String where) {
      final t = number(row, key, where);
      if (t == null) return null;
      final step = stepOf(t);
      if (t < 0.0 || step > steps) {
        problems.add('$where.$key: $t is not within the sequence');
        return null;
      }
      return step;
    }

    // The camera.
    final camera = json['camera'];
    final cameraKeys = <CameraKey>[];
    var ease = false;
    if (camera != null) {
      if (camera is! Map) {
        problems.add('sequence.camera: an object');
      } else {
        ease = camera['ease'] == true;
        for (final (i, row) in rows(camera['keys'], 'camera.keys')) {
          final where = 'camera.keys[$i]';
          final step = moment(row, 't', where);
          final at = vector(row, 'at', where);
          final look = vector(row, 'look', where);
          // The file writes degrees under `fovY`; the engine takes radians,
          // converted here, at the reader.
          final degrees = row.containsKey('fov')
              ? number(row, 'fov', where)
              : 45.0;
          if (step == null || at == null || look == null || degrees == null) {
            continue;
          }
          final fovY = degrees * math.pi / 180.0;
          if (cameraKeys.isNotEmpty && step <= cameraKeys.last.step) {
            problems.add('$where.t: after the key before it');
            continue;
          }
          cameraKeys.add((step: step, at: at, look: look, fovY: fovY));
        }
      }
    }

    final subtitles = <SubtitleCue>[];
    for (final (i, row) in rows(json['subtitles'], 'subtitles')) {
      final where = 'subtitles[$i]';
      final from = moment(row, 'from', where);
      final to = moment(row, 'to', where);
      final text = row['text'];
      if (text is! String) problems.add('$where.text: words');
      if (from == null || to == null || text is! String) continue;
      if (to <= from) {
        problems.add('$where.to: after from');
        continue;
      }
      subtitles.add((from: from, to: to, text: text));
    }

    final fades = <FadeKey>[];
    for (final (i, row) in rows(json['fade'], 'fade')) {
      final where = 'fade[$i]';
      final step = moment(row, 't', where);
      final value = number(row, 'value', where);
      if (step == null || value == null) continue;
      if (value < 0.0 || value > 1.0) {
        problems.add('$where.value: from nought to one');
        continue;
      }
      if (fades.isNotEmpty && step <= fades.last.step) {
        problems.add('$where.t: after the key before it');
        continue;
      }
      fades.add((step: step, value: value));
    }

    final signals = <SignalCue>[];
    for (final (i, row) in rows(json['signals'], 'signals')) {
      final where = 'signals[$i]';
      final step = moment(row, 't', where);
      final name = row['name'];
      final data = row['data'] ?? const <String, Object?>{};
      if (name is! String || name.isEmpty) problems.add('$where.name: a name');
      if (data is! Map) problems.add('$where.data: an object');
      if (step == null || name is! String || name.isEmpty || data is! Map) {
        continue;
      }
      signals.add((
        step: step,
        name: name,
        data: Map<String, Object?>.unmodifiable(data.cast<String, Object?>()),
      ));
    }
    // Stable, so two signals on one step fire in the order they were written.
    final ordered = <SignalCue>[
      for (final (_, signal)
          in (signals.indexed.toList()..sort(
            (a, b) =>
                a.$2.step != b.$2.step ? a.$2.step - b.$2.step : a.$1 - b.$1,
          )))
        signal,
    ];

    final cues = <ActorCue>[];
    for (final (i, row) in rows(json['actors'], 'actors')) {
      final where = 'actors[$i]';
      final step = moment(row, 't', where);
      final actor = row['actor'];
      if (actor is! String || actor.isEmpty) {
        problems.add('$where.actor: the name of an actor');
      }
      final kind = ActorCueKind.values
          .where((k) => k.name == row['do'])
          .firstOrNull;
      if (kind == null) {
        problems.add(
          '$where.do: one of '
          '${ActorCueKind.values.map((k) => k.name).join(', ')}',
        );
      }
      final needsPlace = kind == ActorCueKind.goTo || kind == ActorCueKind.face;
      final at = needsPlace ? vector(row, 'at', where) : null;
      final clip = row['clip'];
      final needsClip = kind == ActorCueKind.play;
      if (needsClip && (clip is! String || clip.isEmpty)) {
        problems.add('$where.clip: the name of a clip');
      }
      if (step == null ||
          actor is! String ||
          actor.isEmpty ||
          kind == null ||
          (needsPlace && at == null) ||
          (needsClip && (clip is! String || clip.isEmpty))) {
        continue;
      }
      cues.add((
        step: step,
        actor: actor,
        kind: kind,
        at: at,
        clip: needsClip && clip is String ? clip : null,
      ));
    }
    // Stable, as the signals are.
    final orderedCues = <ActorCue>[
      for (final (_, cue)
          in (cues.indexed.toList()..sort(
            (a, b) =>
                a.$2.step != b.$2.step ? a.$2.step - b.$2.step : a.$1 - b.$1,
          )))
        cue,
    ];

    if (problems.isNotEmpty) return (sequence: null, problems: problems);
    return (
      sequence: Sequence._(
        steps: steps,
        stepsPerSecond: stepsPerSecond,
        cameraKeys: List<CameraKey>.unmodifiable(cameraKeys),
        ease: ease,
        subtitles: List<SubtitleCue>.unmodifiable(subtitles),
        fades: List<FadeKey>.unmodifiable(fades),
        signals: List<SignalCue>.unmodifiable(ordered),
        actorCues: List<ActorCue>.unmodifiable(orderedCues),
      ),
      problems: const <String>[],
    );
  }

  /// The direction [actor] is under at [step], or null when the cutscene
  /// has not told it anything yet.
  ActorCue? cueFor(String actor, int step) {
    ActorCue? current;
    for (final cue in actorCues) {
      if (cue.step > step) break;
      if (cue.actor == actor) current = cue;
    }
    return current;
  }

  /// Whether the cutscene says where the camera is.
  bool get hasCamera => cameraKeys.isNotEmpty;

  /// Where the camera is at [step]: the eye into [at], what it looks at into
  /// [look], and its vertical field of view, in radians, returned. Before the first
  /// key it holds the first, after the last the last.
  ///
  /// **On the path, at the keys' times.** The eye and the point it looks at
  /// each run along a curve through their keys, and between two keys they
  /// cover the curve between them at one speed — or, with [ease], slowing
  /// into and out of each key — so the camera is at a key on its step
  /// exactly and never cuts a corner the author did not draw.
  double cameraAt(double step, Vector3 at, Vector3 look) {
    final keys = cameraKeys;
    if (keys.isEmpty) throw StateError('this sequence has no camera');
    if (keys.length == 1 || step <= keys.first.step) {
      at.setFrom(keys.first.at);
      look.setFrom(keys.first.look);
      return keys.first.fovY;
    }
    if (step >= keys.last.step) {
      at.setFrom(keys.last.at);
      look.setFrom(keys.last.look);
      return keys.last.fovY;
    }
    var i = 0;
    while (keys[i + 1].step <= step) {
      i++;
    }
    final a = keys[i];
    final b = keys[i + 1];
    var f = (step - a.step) / (b.step - a.step);
    if (ease) f = f * f * (3.0 - 2.0 * f);
    double along(CatmullRom curve) {
      final from = curve.distanceToPoint(i);
      return from + (curve.distanceToPoint(i + 1) - from) * f;
    }

    _path!.sampleAt(along(_path), at);
    _looks!.sampleAt(along(_looks), look);
    return a.fovY + (b.fovY - a.fovY) * f;
  }

  /// What the subtitles say at [step], or null: the one that started last
  /// among those showing.
  String? subtitleAt(int step) {
    String? showing;
    var since = -1;
    for (final cue in subtitles) {
      if (cue.from <= step && step < cue.to && cue.from >= since) {
        showing = cue.text;
        since = cue.from;
      }
    }
    return showing;
  }

  /// How dark the screen is at [step], nought to one: straight between two
  /// keys, held before the first and after the last, nought with none.
  double fadeAt(double step) {
    if (fades.isEmpty) return 0.0;
    if (step <= fades.first.step) return fades.first.value;
    if (step >= fades.last.step) return fades.last.value;
    var i = 0;
    while (fades[i + 1].step <= step) {
      i++;
    }
    final a = fades[i];
    final b = fades[i + 1];
    return a.value + (b.value - a.value) * (step - a.step) / (b.step - a.step);
  }
}
