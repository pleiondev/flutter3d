import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show CollisionLayers;
import 'blend.dart';
import 'shake.dart';
import 'shot.dart';
import 'virtual_camera.dart';

/// Which of a game's virtual cameras is shown, and how the view gets from
/// one to the next.
///
/// **One camera system, many cameras.** A game registers every camera it
/// might look through — the chase behind the car, the orbit round the
/// player, a fixed shot of the finish line, a group shot for a cutscene —
/// and switches between them by priority rather than by code that knows
/// which one is current. The highest-priority enabled camera is live; a tie
/// goes to whichever was enabled, added or [prefer]red last, so switching a
/// camera on is enough to cut to it.
///
/// Every frame [update]:
///
/// 1. picks the live camera, and starts a blend when it changed — the pair's
///    own blend from [blendBetween], else the new camera's `blendIn`, else
///    [defaultBlend];
/// 2. places the live camera, the one being blended from, and any camera
///    that asked to be kept up on standby;
/// 3. writes the shot: the live camera's, or the blend between the two;
/// 4. keeps a blended shot out of the walls, when it has a [world] — two
///    cameras each clear of a wall can blend through one;
/// 5. shakes it, from [shake]'s impulses.
///
/// **A blend interrupted is a blend from where the view is.** Switching again
/// halfway freezes the half-blended shot and blends from that, so a camera
/// changed twice in quick succession sweeps once rather than jumping back to
/// the first camera to start the second blend.
///
/// The view's, entirely: see `VirtualCamera` on determinism. The shake is
/// seeded by the step; everything else here is a function of what the
/// cameras were handed and the frame times.
final class CameraDirector {
  /// A director blending by [defaultBlend] where nothing more particular is
  /// said, keeping blends out of [world]'s walls when it is given one.
  CameraDirector({
    this.defaultBlend = const CameraBlend.ease(0.8),
    this.world,
    this.nearClearance = 0.35,
    this.minDistance = 1.2,
    this.wallMask = CollisionLayers.world,
    ImpulseShake? shake,
  }) : shake = shake ?? ImpulseShake();

  /// The blend between two cameras when neither the pair nor the camera
  /// going live says otherwise.
  CameraBlend defaultBlend;

  /// Where the walls are, for a blended shot. Null keeps nothing out of
  /// anything: each camera's own rig already kept itself clear.
  final CollisionWorld? world;

  /// How far in front of a wall a blended shot stops, how close to what it
  /// watches it may be pulled, and which layers are walls — the same three a
  /// `CameraRig` has, for the same reasons. In metres.
  final double nearClearance;

  /// How close to what it watches a blended shot may be pulled, in metres.
  final double minDistance;
  final int wallMask;

  /// The impulses shaking the view.
  final ImpulseShake shake;

  /// What to draw, after the last [update]: blended, kept clear and shaken.
  final CameraShot shot = CameraShot();

  final List<VirtualCamera> _cameras = <VirtualCamera>[];
  final Map<VirtualCamera, int> _stamps = <VirtualCamera, int>{};
  final Map<VirtualCamera, bool> _wasEnabled = <VirtualCamera, bool>{};
  final Set<VirtualCamera> _placed = <VirtualCamera>{};
  final Map<String, CameraBlend> _pairs = <String, CameraBlend>{};
  int _stamp = 0;

  VirtualCamera? _live;
  VirtualCamera? _from;
  CameraBlend _blend = CameraBlend.cut;
  double _elapsed = 0.0;
  bool _blending = false;
  bool _cutNext = false;
  bool _hasShot = false;

  /// The shot blended from when the blend was interrupted, unshaken.
  final CameraShot _frozen = CameraShot();

  /// The last shot before the shake, which is what an interruption freezes.
  final CameraShot _settled = CameraShot();

  /// Every camera, in the order added.
  List<VirtualCamera> get cameras => List<VirtualCamera>.unmodifiable(_cameras);

  /// The camera being shown, or blended towards. Null before the first
  /// [update], or when no camera is enabled.
  VirtualCamera? get live => _live;

  /// The camera being blended from, or null when the blend began from a
  /// frozen shot, or there is no blend.
  VirtualCamera? get blendingFrom => _blending ? _from : null;

  /// Whether a blend is under way.
  bool get isBlending => _blending;

  /// The blend under way, or the last one.
  CameraBlend get blend => _blend;

  /// How far the blend has gone, nought to one; one when there is none.
  /// For a game that fades its HUD or its letterbox with the blend.
  double get blendWeight => _blending ? _blend.weight(_elapsed) : 1.0;

  /// Adds [camera]. It wins ties with every camera added before it.
  ///
  /// Throws an [ArgumentError] when a camera of that name is already here: a
  /// blend table keyed by name could not tell the two apart.
  void add(VirtualCamera camera) {
    if (_cameras.any((VirtualCamera c) => c.name == camera.name)) {
      throw ArgumentError.value(
        camera.name,
        'camera',
        'a camera of that name is already directed',
      );
    }
    _cameras.add(camera);
    _stamps[camera] = ++_stamp;
    _wasEnabled[camera] = camera.enabled;
  }

  /// Takes [camera] away. If it was live, the next [update] picks another and
  /// blends to it from the shot on screen.
  bool remove(VirtualCamera camera) {
    final removed = _cameras.remove(camera);
    _stamps.remove(camera);
    _wasEnabled.remove(camera);
    _placed.remove(camera);
    if (identical(_from, camera)) {
      _frozen.setFrom(_settled);
      _from = null;
    }
    if (identical(_live, camera)) {
      _frozen.setFrom(_settled);
      _live = null;
    }
    return removed;
  }

  /// The camera called [name], or null.
  VirtualCamera? named(String name) {
    for (final camera in _cameras) {
      if (camera.name == name) return camera;
    }
    return null;
  }

  /// Makes [camera] win ties with every other camera of its priority.
  void prefer(VirtualCamera camera) {
    if (_stamps.containsKey(camera)) _stamps[camera] = ++_stamp;
  }

  /// Says how the view goes from the camera called [from] to the one called
  /// [to]. Either may be `*`, for any camera; the most particular match wins.
  void blendBetween(String from, String to, CameraBlend blend) {
    _pairs['$from>$to'] = blend;
  }

  /// The blend a switch from [from] to [to] would use.
  CameraBlend blendFor(VirtualCamera? from, VirtualCamera to) {
    final name = from?.name ?? '*';
    return _pairs['$name>${to.name}'] ??
        _pairs['$name>*'] ??
        _pairs['*>${to.name}'] ??
        to.blendIn ??
        _pairs['*>*'] ??
        defaultBlend;
  }

  /// Makes the next switch a cut, whatever blend it would have used: for a
  /// game whose next camera starts a cutscene or a new shot of a replay.
  void cutNext() => _cutNext = true;

  /// Ends any blend and puts the live camera where its framing wants it, with
  /// nothing shaking: a respawn, a new level, a loaded save.
  void cut() {
    _blending = false;
    _from = null;
    _live?.cut();
    shake.clear();
  }

  /// Adds [impulse], published by [step] as its [sequence]th event, felt from
  /// where the view is now.
  void impulse(CameraImpulse impulse, {required int step, int sequence = 0}) =>
      shake.impulse(impulse, step: step, sequence: sequence, eye: shot.eye);

  /// Places the cameras and writes [shot] for a frame [dt] seconds after the
  /// last.
  void update(double dt) {
    _noticeSwitchedOn();
    final next = _pick();
    if (next != null && !identical(next, _live)) _switchTo(next);

    final placedNow = <VirtualCamera>{};
    final live = _live;
    if (live != null) {
      live.update(dt);
      placedNow.add(live);
    }
    final from = _blending ? _from : null;
    if (from != null && !placedNow.contains(from)) {
      from.update(dt);
      placedNow.add(from);
    }
    for (final camera in _cameras) {
      if (!camera.enabled || !camera.updateOnStandby) continue;
      if (placedNow.add(camera)) camera.update(dt);
    }
    _placed
      ..clear()
      ..addAll(placedNow);

    if (live != null) {
      if (_blending) {
        _elapsed += dt;
        final weight = _blend.weight(_elapsed);
        _settled.blend(from?.shot ?? _frozen, live.shot, weight);
        _keepClear(_settled);
        if (_elapsed >= _blend.seconds) {
          _blending = false;
          _from = null;
        }
      } else {
        _settled.setFrom(live.shot);
      }
    }

    shake.advance(dt);
    shot.setFrom(_settled);
    shake.apply(shot);
  }

  void _noticeSwitchedOn() {
    for (final camera in _cameras) {
      final was = _wasEnabled[camera] ?? false;
      if (camera.enabled && !was) _stamps[camera] = ++_stamp;
      _wasEnabled[camera] = camera.enabled;
    }
  }

  VirtualCamera? _pick() {
    VirtualCamera? best;
    for (final camera in _cameras) {
      if (!camera.enabled) continue;
      if (best == null ||
          camera.priority > best.priority ||
          (camera.priority == best.priority &&
              _stamps[camera]! > _stamps[best]!)) {
        best = camera;
      }
    }
    return best;
  }

  void _switchTo(VirtualCamera next) {
    final previous = _live;
    final blend = _cutNext || (previous == null && !_blending && !_hasShot)
        ? CameraBlend.cut
        : blendFor(previous, next);
    _cutNext = false;

    // A camera nobody kept up is where it was left: put it where it belongs
    // before anybody sees it, and let the blend be the smooth part.
    if (!_placed.contains(next)) next.cut();

    if (blend.isCut) {
      _blending = false;
      _from = null;
    } else {
      if (_blending || previous == null) {
        // Halfway through a blend, or from a camera that has gone: from the
        // shot on screen, frozen.
        _frozen.setFrom(_settled);
        _from = null;
      } else {
        _from = previous;
      }
      _blending = true;
      _elapsed = 0.0;
    }
    _blend = blend;
    _live = next;
    _hasShot = true;
  }

  /// Pulls a blended shot's eye in until the line from its target is clear.
  void _keepClear(CameraShot blended) {
    final walls = world;
    if (walls == null) return;
    final toEye = blended.eye - blended.target;
    final reach = toEye.length;
    if (reach <= 1e-4) return;
    toEye.scale(1.0 / reach);
    final hit = RayHit();
    if (!walls.raycast(blended.target, toEye, reach, hit, mask: wallMask)) {
      return;
    }
    final pulled = math.max(minDistance, hit.distance - nearClearance);
    blended.eye
      ..setFrom(blended.target)
      ..addScaled(toEye, pulled);
  }
}
