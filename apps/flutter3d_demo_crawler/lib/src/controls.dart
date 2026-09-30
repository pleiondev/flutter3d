/// Who is holding what, and what they are asking their hero to do.
///
/// Up to four seats. Two players can share the keyboard — one on WASD, one on
/// the arrows — and anybody with a controller takes a seat of their own by
/// pressing fire on it: `Gamepad(index: n)` reads the controller in slot n.
/// A seat is taken in the order players join, so the first to press fire is
/// hero one whatever they are holding.
///
/// The keyboard is read as it stands each frame rather than from a queue of
/// events, except for the potion, which is a press: holding the key must not
/// drink every potion the hero is carrying.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:pad_input/pad_input.dart';

/// One way of holding the game: a keyboard layout, or a controller slot.
sealed class Device {
  const Device();

  /// The device's reading this frame: a direction on the ground, fire held,
  /// and whether the potion button went down since the last frame.
  ({double x, double z, bool fire, bool drink}) read(Controls controls);
}

/// Six keys on the keyboard.
final class Keys extends Device {
  const Keys._(
    this.name,
    this.up,
    this.down,
    this.left,
    this.right,
    this.fire,
    this.drink,
  );

  final String name;
  final LogicalKeyboardKey up;
  final LogicalKeyboardKey down;
  final LogicalKeyboardKey left;
  final LogicalKeyboardKey right;
  final LogicalKeyboardKey fire;
  final LogicalKeyboardKey drink;

  static const Keys wasd = Keys._(
    'WASD, Space to fire, Q for a potion',
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.keyQ,
  );

  static const Keys arrows = Keys._(
    'arrows, / to fire, . for a potion',
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.slash,
    LogicalKeyboardKey.period,
  );

  @override
  ({double x, double z, bool fire, bool drink}) read(Controls controls) {
    final held = HardwareKeyboard.instance.logicalKeysPressed;
    double axis(LogicalKeyboardKey minus, LogicalKeyboardKey plus) =>
        (held.contains(plus) ? 1.0 : 0.0) - (held.contains(minus) ? 1.0 : 0.0);
    return (
      x: axis(left, right),
      z: axis(up, down),
      fire: held.contains(fire),
      drink: controls._pressed.remove(drink),
    );
  }
}

/// The controller in one slot.
final class Pad extends Device {
  Pad(this.index) : gamepad = Gamepad(index: index);

  final int index;
  final Gamepad gamepad;
  final PadSnapshot _now = PadSnapshot();
  bool _drinkWasDown = false;

  @override
  ({double x, double z, bool fire, bool drink}) read(Controls controls) {
    gamepad.read(_now);
    if (!_now.connected) {
      return (x: 0.0, z: 0.0, fire: false, drink: false);
    }
    var x = _now.axis(PadAxis.leftStickX);
    // Up the stick is up the screen, which is north, which is −Z.
    var z = -_now.axis(PadAxis.leftStickY);
    if (_now.down(PadButton.dpadLeft)) x -= 1.0;
    if (_now.down(PadButton.dpadRight)) x += 1.0;
    if (_now.down(PadButton.dpadUp)) z -= 1.0;
    if (_now.down(PadButton.dpadDown)) z += 1.0;
    final drinkDown =
        _now.down(PadButton.faceEast) || _now.down(PadButton.faceNorth);
    final drink = drinkDown && !_drinkWasDown;
    _drinkWasDown = drinkDown;
    return (
      x: x,
      z: z,
      fire: _now.down(PadButton.faceSouth) || _now.down(PadButton.triggerRight),
      drink: drink,
    );
  }
}

/// A player: the device they hold and the class they picked.
final class Seat {
  Seat(this.device, this.kind);

  final Device device;
  HeroClass kind;

  /// What the device said last frame, for the select screen's edges.
  ({double x, double z, bool fire, bool drink})? last;
}

final class Controls {
  Controls()
    : devices = <Device>[
        Keys.wasd,
        Keys.arrows,
        for (var i = 0; i < 4; i++) Pad(i),
      ];

  /// Every way of holding the game this build knows.
  final List<Device> devices;

  /// The players, in the order they joined.
  final List<Seat> seats = <Seat>[];

  /// Keys that went down since they were last read, for the presses.
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  /// Hand every key event here.
  bool onKey(KeyEvent event) {
    if (event is KeyDownEvent) _pressed.add(event.logicalKey);
    return false;
  }

  /// One frame of the select screen: a device whose fire went down joins, a
  /// seated one moving sideways changes class. Answers whether somebody
  /// seated pressed the potion button, which starts the game.
  bool choose() {
    var start = false;
    for (final device in devices) {
      final now = device.read(this);
      Seat? seat;
      for (final s in seats) {
        if (identical(s.device, device)) seat = s;
      }
      if (seat == null) {
        if (now.fire && seats.length < 4) {
          seats.add(Seat(device, _freeClass())..last = now);
        }
        continue;
      }
      final before = seat.last;
      if (before != null && before.x.abs() < 0.5 && now.x.abs() >= 0.5) {
        seat.kind = _nextClass(seat.kind, now.x > 0 ? 1 : -1);
      }
      if (now.drink) start = true;
      seat.last = now;
    }
    _pressed.clear();
    return start && seats.isNotEmpty;
  }

  /// One frame of play: each seat's reading written onto its hero.
  void drive(List<Hero> heroes) {
    for (var i = 0; i < seats.length && i < heroes.length; i++) {
      final now = seats[i].device.read(this);
      final hero = heroes[i];
      // A diagonal on the keys is two full axes; walked as it stands it would
      // be forty per cent faster than straight.
      final length = math.sqrt(now.x * now.x + now.z * now.z);
      final scale = length > 1.0 ? 1.0 / length : 1.0;
      hero.wish.setValues(now.x * scale, 0.0, now.z * scale);
      hero.fire = now.fire;
      // Set, never cleared here: the step clears it once it has drunk.
      if (now.drink) hero.drink = true;
    }
    _pressed.clear();
  }

  HeroClass _freeClass() {
    for (final kind in HeroClass.all) {
      if (!seats.any((Seat s) => identical(s.kind, kind))) return kind;
    }
    return HeroClass.all.first;
  }

  HeroClass _nextClass(HeroClass from, int step) {
    final all = HeroClass.all;
    final at = all.indexOf(from);
    return all[(at + step) % all.length];
  }
}
