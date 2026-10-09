/// A short cutscene as a document: the camera on a curve through four keys,
/// two subtitles, a fade in from near black, and two signals the game answers by
/// lighting a lamp and raising a gate. Skipped, it ends where watching it
/// ends.
///
/// Quoted by `cutscenes.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;

/// What the cutscene changes in the game: what its signals did.
final class _Stage {
  bool lampLit = false;
  double gateHeight = 0.0;
  final List<String> heard = <String>[];

  // #region answer
  /// The game's answer to each signal, subscribed on the bus the cutscene
  /// publishes onto: heard in order, on the step it fired.
  Registration listenTo(EventRegistry bus) => bus.onStep<SequenceSignal>(
    'cutscenes.answer',
    (Delivered<SequenceSignal> delivered) {
      final SequenceSignal signal = delivered.event;
      heard.add(signal.signal);
      switch (signal.signal) {
        case 'lamp':
          lampLit = true;
        case 'gate':
          gateHeight = (signal.data['height'] as num?)?.toDouble() ?? 2.0;
      }
    },
  );
  // #endregion answer

  bool sameAs(_Stage other) =>
      lampLit == other.lampLit &&
      gateHeight == other.gateHeight &&
      listEquals(heard, other.heard);

  @override
  String toString() => 'lamp $lampLit, gate $gateHeight, heard $heard';
}

final class CutscenesDemo extends ShowcaseDemo {
  late final Sequence _sequence;
  late SequencePlayer _player;
  late _Stage _stage;

  late final LightNode _lamp;
  late final MeshNode _gate;
  late final MeshNode _flame;

  double _carry = 0.0;
  double _after = 0.0;

  /// The subtitle showing, for whoever draws text over the picture.
  @visibleForTesting
  String? get subtitle => _player.subtitle;

  // #region document
  /// Seconds in the document; every moment is turned into the step it
  /// falls on at the game's rate when it is read.
  static const Map<String, Object?> document = <String, Object?>{
    'seconds': 8,
    'camera': <String, Object?>{
      'ease': true,
      'keys': <Object?>[
        <String, Object?>{
          't': 0,
          'at': <double>[0, 3, 13],
          'look': <double>[0, 1, 0],
        },
        <String, Object?>{
          't': 3,
          'at': <double>[7, 2.5, 5],
          'look': <double>[0, 1, -1],
        },
        <String, Object?>{
          't': 5.5,
          'at': <double>[4, 1.8, -1],
          'look': <double>[0, 1.2, -4],
        },
        <String, Object?>{
          't': 8,
          'at': <double>[1.5, 2.2, 3],
          'look': <double>[0, 1.4, -4],
          'fov': 38,
        },
      ],
    },
    'subtitles': <Object?>[
      <String, Object?>{
        'from': 0.5,
        'to': 3,
        'text': 'The hall has been dark a long time.',
      },
      <String, Object?>{
        'from': 3.5,
        'to': 6.5,
        'text': 'Something at the altar is waking.',
      },
    ],
    'fade': <Object?>[
      <String, Object?>{'t': 0, 'value': 0.8},
      <String, Object?>{'t': 1.5, 'value': 0},
    ],
    'signals': <Object?>[
      <String, Object?>{'t': 3, 'name': 'lamp'},
      <String, Object?>{
        't': 5.5,
        'name': 'gate',
        'data': <String, Object?>{'height': 2.5},
      },
    ],
  };
  // #endregion document

  static const int stepsPerSecond = 60;

  // #region read
  static Sequence readSequence() {
    final SequenceRead read = Sequence.read(
      document,
      stepsPerSecond: stepsPerSecond,
    );
    final Sequence? sequence = read.sequence;
    if (sequence == null) throw FormatException(read.problems.join('\n'));
    return sequence;
  }
  // #endregion read

  void _start() {
    _stage = _Stage();
    _player = _playedTo(_sequence, _stage);
    _after = 0.0;
  }

  // #region bus
  /// A player whose signals [stage] answers: they are published onto a bus
  /// [stage] listens on. A game stepped by an `EngineLoop` hands its own;
  /// this page steps the cutscene by hand, so a [DirectBus] does.
  static SequencePlayer _playedTo(Sequence sequence, _Stage stage) {
    final DirectBus bus = DirectBus();
    stage.listenTo(bus);
    return SequencePlayer(sequence, events: bus);
  }
  // #endregion bus

  @override
  Scene build(DemoContext context) {
    _sequence = readSequence();
    _start();
    MeshNode box(Vector3 at, Vector3 size, Vector4 color, String name) =>
        MeshNode(
          DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
          RenderMaterial(name: name, baseColor: _fromSrgb(color)),
          name: name,
        )..setPosition(at.x, at.y, at.z);
    _lamp = LightNode(
      name: 'altar lamp',
      type: LightType.point,
      intensity: 0.0 * Photometric.legacyUnit,
    )..setPosition(0.0, 2.2, -4.0);
    _gate = box(
      Vector3(0.0, 1.5, -7.0),
      Vector3(4.0, 3.0, 0.3),
      Vector4(0.35, 0.33, 0.3, 1.0),
      'gate',
    );
    _flame = box(
      Vector3(0.0, 1.45, -4.0),
      Vector3.all(0.3),
      Vector4(0.3, 0.3, 0.3, 1.0),
      'flame',
    );
    _show();
    return Scene()
      ..ambientIntensity = 0.25 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'moon', intensity: 1.2 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.2, -0.8, -0.5)),
      )
      ..add(_lamp)
      ..add(
        box(
          Vector3(0.0, -0.5, -2.0),
          Vector3(14.0, 1.0, 14.0),
          Vector4(0.4, 0.4, 0.42, 1.0),
          'floor',
        ),
      )
      ..add(
        box(
          Vector3(0.0, 0.65, -4.0),
          Vector3(1.6, 1.3, 1.0),
          Vector4(0.6, 0.56, 0.48, 1.0),
          'altar',
        ),
      )
      ..add(_flame)
      ..add(_gate);
  }

  /// The game's state drawn: the lamp, the flame on the altar and the gate.
  void _show() {
    _lamp.intensity = _stage.lampLit ? 30.0 * Photometric.legacyUnit : 0.0;
    _flame.material.baseColor = LinearColor.fromSrgb(
      _stage.lampLit ? 1.0 : 0.3,
      _stage.lampLit ? 0.7 : 0.3,
      _stage.lampLit ? 0.2 : 0.3,
      1.0,
    );
    _gate.setPosition(0.0, 1.5 + _stage.gateHeight, -7.0);
  }

  // #region step
  /// One fixed step of the game while the cutscene plays: the player moves
  /// on a step and publishes what it reaches, and the game's subscriber
  /// answers.
  static void _stepOnce(SequencePlayer player) => player.advance();
  // #endregion step

  // #region skip
  /// A skip is the rest of the cutscene stepped without being drawn: every
  /// signal still fires, in order, so the game ends where watching it ends.
  static void _skip(SequencePlayer player) {
    while (!player.isFinished) {
      _stepOnce(player);
    }
  }
  // #endregion skip

  @override
  void update(DemoContext context, double dt) {
    _carry += dt.clamp(0.0, 0.1);
    while (_carry >= 1 / stepsPerSecond) {
      _carry -= 1 / stepsPerSecond;
      _stepOnce(_player);
    }
    if (_player.isFinished) {
      _after += dt;
      if (_after > 3.0) _start();
    }
    // #region camera
    // Drawn between two steps: alpha is how far the frame is past the last.
    final double alpha = _carry * stepsPerSecond;
    final Vector3 eye = Vector3.zero(), look = Vector3.zero();
    final double? fovY = _player.cameraAt(eye, look, alpha: alpha);
    if (fovY != null) {
      context.camera
        ..setPosition(eye.x, eye.y, eye.z)
        ..lookAt(look);
    }
    // #endregion camera
    _show();
  }

  // #region fade
  /// The fade darkens the whole picture: a fade of one is black.
  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    exposure: RenderSettings.defaultExposure * (1.0 - _player.fade()),
  );
  // #endregion fade

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Skip to the end',
      value: () => false,
      onChanged: (bool v) {
        if (v) _skip(_player);
      },
    ),
    ToggleControl(
      'Play again',
      value: () => false,
      onChanged: (bool v) {
        if (v) _start();
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    // #region check
    final Sequence sequence = readSequence();
    // Watched: one step a frame to the end.
    final _Stage seen = _Stage();
    final SequencePlayer watched = _playedTo(sequence, seen);
    while (!watched.isFinished) {
      _stepOnce(watched);
    }
    // Skipped a second and a half in, before either signal.
    final _Stage hurried = _Stage();
    final SequencePlayer skipped = _playedTo(sequence, hurried);
    for (var i = 0; i < 90; i++) {
      _stepOnce(skipped);
    }
    _skip(skipped);
    if (!seen.sameAs(hurried) || skipped.step != watched.step) {
      throw StateError('skipped: $hurried; watched: $seen');
    }
    if (!listEquals(seen.heard, <String>['lamp', 'gate']) ||
        seen.gateHeight != 2.5) {
      throw StateError('the signals were not answered: $seen');
    }
    // Restored past the lamp, the lamp does not fire a second time.
    final _Stage later = _Stage();
    final SequencePlayer restored = _playedTo(sequence, later)
      ..restore(<String, Object?>{'step': 4 * stepsPerSecond});
    _skip(restored);
    if (!listEquals(later.heard, <String>['gate'])) {
      throw StateError('a restore fired ${later.heard}');
    }
    // The camera ends on its last key, the fade on clear.
    final Vector3 eye = Vector3.zero(), look = Vector3.zero();
    if (skipped.cameraAt(eye, look) != 38.0 * math.pi / 180.0 ||
        eye.distanceTo(Vector3(1.5, 2.2, 3.0)) > 1e-6 ||
        skipped.fade() != 0.0) {
      throw StateError('the camera or the fade did not end where written');
    }
    // #endregion check
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
