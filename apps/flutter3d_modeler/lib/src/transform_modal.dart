/// A transform in progress: what it is constrained to, how far it has got, and
/// what the person has typed.
///
/// **The modal transform is what the basic operations actually are**, and it is
/// not the gizmo. Pressing `G`, moving the mouse, typing `X`, typing `5`, and
/// pressing Enter is how a move gets done in every modeller people come from;
/// the gizmo is the discoverable version of the same thing and should be the
/// same code underneath, or the two answer differently and one of them is
/// wrong. So this holds the state and the arithmetic, the keyboard drives it,
/// and `view-25n`'s handles will drive it too.
///
/// **Escape has to put the model back exactly**, which is why a transform is
/// one open transaction from the first move to the last: cancelling is undoing
/// the step and dropping it, not applying the opposite transform. The opposite
/// of a scale by 0.3 is a scale by 10/3, and the two do not compose back to the
/// identity in floating point.
///
/// Everything here is arithmetic over numbers a test can hand it. What needs a
/// window is the key that arrives and the pointer that moves, and that is the
/// widget's half.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// What a transform in progress is doing.
enum TransformKind { move, rotate, scale }

/// What it is confined to.
///
/// **Three axes and three planes, because that is what two presses of the same
/// key mean.** `X` confines to the X axis; `X` again confines to the plane at
/// right angles to it, which is what `Shift+X` means elsewhere and is the more
/// useful of the two often enough to be worth the second press.
enum TransformAxis {
  free,
  x,
  y,
  z,
  yz,
  xz,
  xy;

  /// Which of the three world axes this lets through.
  ({bool x, bool y, bool z}) get allows => switch (this) {
    TransformAxis.free => (x: true, y: true, z: true),
    TransformAxis.x => (x: true, y: false, z: false),
    TransformAxis.y => (x: false, y: true, z: false),
    TransformAxis.z => (x: false, y: false, z: true),
    TransformAxis.yz => (x: false, y: true, z: true),
    TransformAxis.xz => (x: true, y: false, z: true),
    TransformAxis.xy => (x: true, y: true, z: false),
  };

  /// What pressing [key] a second time turns this into.
  ///
  /// The same key toggles between the axis and the plane across it, and a
  /// different key starts again on that axis. Pressing the key of the axis you
  /// are already confined to the plane of goes back to free, which is how a
  /// person un-constrains without reaching for Escape.
  TransformAxis pressed(TransformAxis key) {
    if (this == key) return _planeAcross(key);
    if (this == _planeAcross(key)) return TransformAxis.free;
    return key;
  }

  static TransformAxis _planeAcross(TransformAxis axis) => switch (axis) {
    TransformAxis.x => TransformAxis.yz,
    TransformAxis.y => TransformAxis.xz,
    TransformAxis.z => TransformAxis.xy,
    _ => TransformAxis.free,
  };

  /// What the status line says.
  String get says => switch (this) {
    TransformAxis.free => '',
    TransformAxis.x => 'along X',
    TransformAxis.y => 'along Y',
    TransformAxis.z => 'along Z',
    TransformAxis.yz => 'in the YZ plane',
    TransformAxis.xz => 'in the XZ plane',
    TransformAxis.xy => 'in the XY plane',
  };
}

/// How far a transform has got, and what it is confined to.
final class TransformModal {
  TransformModal(this.kind);

  final TransformKind kind;

  TransformAxis axis = TransformAxis.free;

  /// What the pointer has added up to: metres for a move, radians for a turn,
  /// a factor for a scale.
  ///
  /// Accumulated rather than taken from the pointer's distance from where it
  /// started, because the two disagree the moment a constraint is added
  /// halfway through — and a move that jumps when `X` is pressed is a move
  /// nobody can aim.
  Vector3 dragged = Vector3.zero();

  /// What the person has typed, or null.
  ///
  /// **A string rather than a number, because a half-typed number is not
  /// one.** `-` is a minus sign waiting for digits, `5.` is five waiting for a
  /// fraction, and both have to be shown back while they are being typed.
  String? typed;

  /// Whether the snap modifier is held.
  bool snapping = false;

  /// How coarse a snap is, per kind.
  ///
  /// A tenth of a unit, fifteen degrees and a tenth of a factor: the three
  /// steps every modeller uses, and the reason they are not one number is that
  /// a tenth of a radian is not a step anybody thinks in.
  static const double moveStep = 0.1;
  static const double turnStep = math.pi / 12;
  static const double scaleStep = 0.1;

  /// The typed number, or null when nothing usable has been typed.
  double? get typedValue {
    final String? said = typed;
    if (said == null) return null;
    final double? read = double.tryParse(said.replaceAll(',', '.'));
    return read != null && read.isFinite ? read : null;
  }

  /// Adds a keystroke to the typed number, or refuses it.
  ///
  /// Returns whether the key was taken, so a caller can pass on the ones that
  /// were not — `X` is a constraint while a number is being typed as much as
  /// before one.
  bool type(String character) {
    if (character == 'backspace') {
      final String? said = typed;
      if (said == null || said.isEmpty) return false;
      typed = said.length == 1 ? null : said.substring(0, said.length - 1);
      return true;
    }
    if (character.length != 1) return false;
    final bool digit =
        character.codeUnitAt(0) >= 0x30 && character.codeUnitAt(0) <= 0x39;
    final bool point = character == '.' || character == ',';
    final bool sign = character == '-';
    if (!digit && !point && !sign) return false;
    final String said = typed ?? '';
    // A sign only at the front, and a point only once: `5-3` and `1.2.3` are
    // not numbers, and letting them be typed means showing a value that will
    // not parse and applying nothing when Enter is pressed.
    if (sign && said.isNotEmpty) return false;
    if (point && said.contains(RegExp(r'[.,]'))) return false;
    typed = said + character;
    return true;
  }

  /// The amount this transform is at, along each axis.
  ///
  /// A typed number wins over the pointer, which is the whole point of being
  /// able to type one: `G X 5` is five, however far the mouse went. With no
  /// constraint a typed number goes along X, because a number with no axis has
  /// to mean something and the first axis is what every modeller picks.
  Vector3 get amount {
    final double? said = typedValue;
    final Vector3 raw = said == null
        ? Vector3.copy(dragged)
        : switch (axis) {
            TransformAxis.y => Vector3(0, said, 0),
            TransformAxis.z => Vector3(0, 0, said),
            _ => Vector3(said, 0, 0),
          };
    final allows = axis.allows;
    if (!allows.x) raw.x = 0;
    if (!allows.y) raw.y = 0;
    if (!allows.z) raw.z = 0;
    if (!snapping || said != null) return raw;
    final double step = switch (kind) {
      TransformKind.move => moveStep,
      TransformKind.rotate => turnStep,
      TransformKind.scale => scaleStep,
    };
    return Vector3(_snap(raw.x, step), _snap(raw.y, step), _snap(raw.z, step));
  }

  static double _snap(double value, double step) =>
      (value / step).roundToDouble() * step;

  /// What the status line shows while this is going on.
  String get says {
    final String what = switch (kind) {
      TransformKind.move => 'move',
      TransformKind.rotate => 'turn',
      TransformKind.scale => 'scale',
    };
    final Vector3 by = amount;
    final String number = switch (kind) {
      TransformKind.move => '${_show(by.x)}, ${_show(by.y)}, ${_show(by.z)}',
      TransformKind.rotate => '${_show(by.x * 180 / math.pi)}°',
      TransformKind.scale => _show(1 + by.x),
    };
    final String where = axis.says;
    final String typing = typed == null ? '' : '  ⌨ $typed';
    return where.isEmpty
        ? '$what $number$typing'
        : '$what $where $number$typing';
  }

  static String _show(double value) => value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
