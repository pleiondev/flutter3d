import 'dart:typed_data';

import 'package:flutter/services.dart' show KeyEvent;

import 'android_mapping.dart';
import 'darwin_mapping.dart';
import 'desktop_mapping.dart';
import 'gamepad_platform_interface.dart';
import 'pad_mirror.dart';
import 'pad_snapshot.dart';

/// The controllers a platform reports, each in the slot of the player
/// holding it: what the method channel reads a pad through.
///
/// **One mirror a controller.** A platform mirror remembers one pad; this
/// keeps one per slot and hands each message to the one it is about. The
/// first controller to connect is slot nought and keeps it while it stays
/// connected, a second is slot one, and a slot a controller leaves is the
/// next one's to take, as the numbered lights on a console's pads are.
abstract interface class PadSlots {
  /// Takes one message from the platform.
  void note(Object? event);

  /// Takes a key from Flutter's keyboard, for a platform whose buttons
  /// arrive there.
  void noteKey(KeyEvent event);

  /// How many controllers are connected.
  int get connectedCount;

  /// Fills [out] from the controller in [slot], or reports it disconnected.
  void fill(int slot, PadSnapshot out);
}

/// Controllers whose native side names the slot of each message itself —
/// macOS and iOS, Windows and Linux — each slot's messages read by a mirror
/// of the platform's kind.
///
/// A sample is the slot and then what the mirror reads; an event map
/// carries `slot`. A message without one is slot nought's, which is what a
/// plugin sent when it reported one controller.
abstract base class _NamedSlots<M extends PadMirror> implements PadSlots {
  late final List<M?> _slots = List<M?>.filled(GamepadPlatform.maxPads, null);

  /// A mirror for a slot's first message.
  M _mirror();

  @override
  void note(Object? event) {
    if (event is Float64List) {
      if (event.isEmpty) return;
      final slot = event[0].toInt();
      if (slot < 0 || slot >= _slots.length) return;
      (_slots[slot] ??= _mirror()).note(Float64List.sublistView(event, 1));
      return;
    }
    if (event is! Map) return;
    if (event['event'] == 'relaxed' && event['slot'] == null) {
      // The application going away lets go of every controller.
      for (final mirror in _slots) {
        mirror?.note(event);
      }
      return;
    }
    final slot = event['slot'] is int ? event['slot'] as int : 0;
    if (slot < 0 || slot >= _slots.length) return;
    (_slots[slot] ??= _mirror()).note(event);
  }

  @override
  void noteKey(KeyEvent event) {}

  @override
  int get connectedCount =>
      _slots.where((mirror) => mirror?.connected ?? false).length;

  @override
  void fill(int slot, PadSnapshot out) {
    final mirror = slot >= 0 && slot < _slots.length ? _slots[slot] : null;
    if (mirror == null) {
      out.disconnect();
    } else {
      mirror.fill(out);
    }
  }
}

/// Controllers on macOS and iOS, the slot each one's player light shows —
/// see [DarwinPadState].
final class DarwinPads extends _NamedSlots<DarwinPadState> {
  @override
  DarwinPadState _mirror() => DarwinPadState();
}

/// Controllers on Windows, XInput's four user indices as the slots — see
/// [XInputPadState].
final class XInputPads extends _NamedSlots<XInputPadState> {
  @override
  XInputPadState _mirror() => XInputPadState();
}

/// Controllers on Linux, `/dev/input/js0` to `js3` as the slots — see
/// [JoystickPadState].
final class JoystickPads extends _NamedSlots<JoystickPadState> {
  @override
  JoystickPadState _mirror() => JoystickPadState();
}

/// Controllers on Android: every message names its device, and this gives
/// each device a slot as it connects.
///
/// **Buttons by device.** Android sends a pad's buttons as key events, and
/// through Flutter's keyboard they arrive without the device they came
/// from: two controllers pressing A are one A. The plugin forwards them by
/// device as `key` events, and once one has arrived the keyboard's copies
/// are left alone, so a button is not counted twice. Before any has, as
/// with a plugin that does not forward them, the keyboard's go to the
/// first controller, as they always did.
final class AndroidPads implements PadSlots {
  final List<AndroidPadState?> _slots = List<AndroidPadState?>.filled(
    GamepadPlatform.maxPads,
    null,
  );
  final Map<int, int> _slotOf = <int, int>{};
  bool _buttonsByDevice = false;

  int? _slotFor(Object? device) => device is int ? _slotOf[device] : null;

  @override
  void note(Object? event) {
    if (event is Float64List) {
      if (event.isEmpty) return;
      final slot = _slotOf[event[0].toInt()];
      if (slot != null) _slots[slot]?.noteMotion(event);
      return;
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'connected':
        final device = event['device'];
        if (device is! int) return;
        final slot = _slotOf[device] ?? _slots.indexWhere((m) => m == null);
        if (slot < 0) return;
        _slotOf[device] = slot;
        (_slots[slot] ??= AndroidPadState()).note(event);
      case 'disconnected':
        final slot = _slotFor(event['device']);
        if (slot == null) {
          // From a plugin that named no device: every controller went.
          for (var i = 0; i < _slots.length; i++) {
            _slots[i]?.disconnect();
            _slots[i] = null;
          }
          _slotOf.clear();
          return;
        }
        _slots[slot]?.disconnect();
        _slots[slot] = null;
        _slotOf.remove(event['device']);
      case 'relaxed':
        for (final mirror in _slots) {
          mirror?.relax();
        }
      case 'key':
        _buttonsByDevice = true;
        final slot = _slotFor(event['device']);
        final code = event['code'];
        final down = event['down'];
        if (slot == null || code is! int || down is! bool) return;
        final button = AndroidPadState.buttonsByCode[code];
        if (button == null) return;
        _slots[slot]?.noteButton(button, down: down);
    }
  }

  @override
  void noteKey(KeyEvent event) {
    if (_buttonsByDevice) return;
    _slots[0]?.noteKey(event);
  }

  @override
  int get connectedCount =>
      _slots.where((mirror) => mirror?.connected ?? false).length;

  @override
  void fill(int slot, PadSnapshot out) {
    final mirror = slot >= 0 && slot < _slots.length ? _slots[slot] : null;
    if (mirror == null) {
      out.disconnect();
    } else {
      mirror.fill(out);
    }
  }
}
