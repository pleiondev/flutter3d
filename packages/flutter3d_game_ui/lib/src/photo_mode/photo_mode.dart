import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_camera/flutter3d_camera.dart' show PhotoCamera;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import '../l10n/game_localizations.dart';
import 'photo_controls.dart';

/// Photo mode — `N8`: the run stopped, a camera to fly, a filter to pick and
/// a picture larger than the window.
///
/// The parts are the engine's: [PhotoCamera] keeps the camera on a tether
/// and out of the walls, [PhotoFilter] is a change to the composite's look,
/// and `savePhoto` draws, encodes and saves. This holds them together and
/// owns the keys while it is open; what stays the game's is [controls] — how
/// its keys fly the camera — its [lens], and the line [keysHint] shows.
///
/// ```dart
/// final photo = PhotoMode(
///   controls: const ActionPhotoControls(
///     up: GameAction.jump,
///     down: myDownAction,
///     sensitivity: 0.0022,
///   ),
/// );
/// ```
final class PhotoMode {
  PhotoMode({
    required this.controls,
    this.lens = const PerspectiveProjection(),
    this.takesEveryKey = false,
    this.keysHint,
  });

  /// How the game's own keys fly the camera.
  final PhotoControls controls;

  /// The lens the picture is taken through; its field of view is the
  /// camera's, zoomed. [enter] may hand a new one, as a chase camera's lens
  /// changes with speed.
  PerspectiveProjection lens;

  /// Whether every key is taken while photo mode is open, rather than only
  /// its own. A game whose keys would be held down in the run when it comes
  /// back — a car's throttle, a dig — says yes.
  final bool takesEveryKey;

  /// The line of keys [PhotoBar] shows, for a game whose keys are not the
  /// walking ones; null for [Flutter3dGameLocalizations.photoWalkingKeys] —
  /// WASD fly, Space and C up and down — in the player's language. The
  /// exposure dials' line is always [Flutter3dGameLocalizations.photoExposureKeys].
  final String? keysHint;

  PhotoCamera? _camera;
  int _filter = 0;

  /// The aperture, shutter and ISO the picture is exposed with — `B6.22`.
  ///
  /// The same model the renderer exposes with (`RenderSettings.camera`):
  /// opening the aperture a stop doubles the light, and with depth of field
  /// on it also narrows what is sharp, since [settings] hands the f-number
  /// to the lens. Starts at the game's own camera when [enter] is given one,
  /// and the reference camera otherwise; the dials move in thirds of a stop.
  PhysicalCamera exposure = const PhysicalCamera();

  /// Whether a dial has been turned since [enter]. Until one is, the game's
  /// exposure — auto exposure included — is left as the game had it.
  bool get usesManualExposure => _manual;
  bool _manual = false;

  /// Whether the run is stopped for a picture.
  bool get isActive => _camera != null;

  /// Whether a picture is being drawn; the keys wait for it, and the game
  /// stops redrawing its surface — see `capturePhoto`.
  bool isBusy = false;

  /// The last thing a picture had to say: where it went, or why not — the
  /// shelf's sentence, which the game may replace with its own words.
  String? said;

  PhotoFilter get filter => PhotoFilter.all[_filter];

  /// Which way the photo camera looks, or null when photo mode is shut: a
  /// game that colours its fog along the view colours it along this.
  Vector3? get gaze => _camera?.forward;

  /// Stops the run and takes the camera from where the game had it: from
  /// [eye] towards [target], on a tether round [anchor] (the eye itself when
  /// none is given), swept against [world].
  ///
  /// [lens], when given, replaces [lens]; [fieldOfView] defaults to the
  /// lens's own.
  ///
  /// [camera] is the game's own exposure camera, where the dials start;
  /// the reference camera when none is given.
  void enter({
    required CollisionWorld world,
    required Vector3 eye,
    required Vector3 target,
    Vector3? anchor,
    PerspectiveProjection? lens,
    double? fieldOfView,
    PhysicalCamera? camera,
  }) {
    if (lens != null) this.lens = lens;
    exposure = camera ?? const PhysicalCamera();
    _manual = false;
    _camera = PhotoCamera(world: world)
      ..begin(
        eye: eye,
        target: target,
        anchor: anchor ?? eye,
        fieldOfView: fieldOfView ?? this.lens.fovY,
      );
    said = null;
  }

  void leave() => _camera = null;

  /// One frame of flying on what [controls] read: [input] and [look] for
  /// [ActionPhotoControls], nothing for [KeyPhotoControls].
  void fly(double dt, {InputState? input, Vector2? look}) {
    final camera = _camera;
    if (camera == null || isBusy) return;
    controls.steer(camera, dt, input: input, look: look);
  }

  /// Turns the camera by a drag of [dx], [dy] pixels, at [perPixel] radians
  /// a pixel — the game's own look speed, so the view turns at the rate the
  /// hand already knows.
  void turn(double dx, double dy, {required double perPixel}) {
    if (isBusy) return;
    _camera?.look(-dx * perPixel, -dy * perPixel);
  }

  /// Puts the photo camera on [node].
  void applyTo(CameraNode node) {
    final camera = _camera;
    if (camera == null) return;
    node
      ..setPositionFrom(camera.eye)
      ..lookAt(camera.target, up: camera.up)
      ..projection = lens.copyWith(fovY: camera.fieldOfView);
  }

  /// [game] with the chosen filter on it.
  LookSettings look(LookSettings game) => filter.applyTo(game);

  /// [game] exposed through [exposure] once a dial has been turned — the
  /// physical camera on, auto exposure off, as a camera taken off automatic
  /// — and, while [game]'s depth of field is on, focused at [exposure]'s
  /// aperture. [game] as it is until then.
  RenderSettings settings(RenderSettings game) {
    if (!_manual) return game;
    final lens = game.depthOfField;
    return game.copyWith(
      camera: exposure,
      physicalCamera: true,
      autoExposure: const AutoExposureSettings(),
      depthOfField: lens.enabled
          ? lens.copyWith(aperture: exposure.aperture)
          : lens,
    );
  }

  /// Moves one of [exposure]'s dials by a third of a stop.
  void _dial(PhysicalCamera Function(PhysicalCamera) turn) {
    exposure = turn(exposure);
    _manual = true;
  }

  /// The keys photo mode owns while it is open, or null for one it does not.
  ///
  /// [onCapture] is asked for a picture at a multiple of the window's size:
  /// Enter twice, Shift+Enter four times. With [takesEveryKey], every other
  /// key is taken too, key-ups included.
  KeyEventResult? key(KeyEvent event, {required void Function(int) onCapture}) {
    final camera = _camera;
    if (camera == null) return null;
    if (event is KeyUpEvent) {
      return takesEveryKey ? KeyEventResult.handled : null;
    }
    if (isBusy) return KeyEventResult.handled;
    final repeatable = event is KeyDownEvent || event is KeyRepeatEvent;
    switch (event.logicalKey) {
      // Brackets rather than the arrows, which may fly or turn the camera.
      case LogicalKeyboardKey.bracketRight when event is KeyDownEvent:
        _filter = (_filter + 1) % PhotoFilter.all.length;
      case LogicalKeyboardKey.bracketLeft when event is KeyDownEvent:
        _filter = (_filter - 1) % PhotoFilter.all.length;
      case LogicalKeyboardKey.comma when repeatable:
        camera.tilt(-0.05);
      case LogicalKeyboardKey.period when repeatable:
        camera.tilt(0.05);
      case LogicalKeyboardKey.equal when repeatable:
        camera.zoom(1.1);
      case LogicalKeyboardKey.minus when repeatable:
        camera.zoom(1.0 / 1.1);
      case LogicalKeyboardKey.enter when event is KeyDownEvent:
        onCapture(HardwareKeyboard.instance.isShiftPressed ? 4 : 2);
      // The exposure dials, a third of a stop a press: the aperture opens
      // on 1 and closes on 2, the shutter shortens on 3 and lengthens on 4,
      // the sensitivity falls on 5 and rises on 6.
      case LogicalKeyboardKey.digit1 when repeatable:
        _dial((c) => c.stopAperture(-1));
      case LogicalKeyboardKey.digit2 when repeatable:
        _dial((c) => c.stopAperture(1));
      case LogicalKeyboardKey.digit3 when repeatable:
        _dial((c) => c.stopShutter(-1));
      case LogicalKeyboardKey.digit4 when repeatable:
        _dial((c) => c.stopShutter(1));
      case LogicalKeyboardKey.digit5 when repeatable:
        _dial((c) => c.stopIso(-1));
      case LogicalKeyboardKey.digit6 when repeatable:
        _dial((c) => c.stopIso(1));
      case LogicalKeyboardKey.digit0 when event is KeyDownEvent:
        _manual = false;
      default:
        // The flying keys are read as held in [fly]; the rest are the
        // game's, which a stopped run either leaves alone or never sees.
        return takesEveryKey ? KeyEventResult.handled : null;
    }
    return KeyEventResult.handled;
  }
}

/// The strip along the bottom of the screen in photo mode: the filter, the
/// keys, and the last picture's sentence.
class PhotoBar extends StatelessWidget {
  const PhotoBar({required this.mode, super.key});

  final PhotoMode mode;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dGameLocalizations.of(context);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  mode.isBusy
                      ? words.takingThePicture
                      : words.photoMode(
                          filter: mode.filter.name,
                          exposure: mode.usesManualExposure
                              ? mode.exposure.label
                              : null,
                        ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(mode.keysHint ?? words.photoWalkingKeys),
                Text(words.photoExposureKeys),
                if (mode.said case final said?) Text(said),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
