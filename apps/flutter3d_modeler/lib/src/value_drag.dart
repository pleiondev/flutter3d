/// An operation whose one number follows the pointer — `ux-29`.
///
/// **Extrude and Bevel guessed, and the guess was the whole interaction.**
/// `tool_commands.dart` answers `E` with a tenth of the model's own size and
/// `Ctrl+B` with a twentieth, which is a reasonable first number and is never
/// the number anybody wanted; what a modeller does is press the key, pull the
/// mouse until the face is where it should be, and click. That is exactly
/// `ux-11`'s modal transform with one number instead of three, and this is
/// that number.
///
/// **It amends rather than re-running.** The operation lands once, at the
/// guess, and every pointer move replaces it through `ModelHistory.amend` —
/// the same door the operation card's own slider already uses, which re-runs
/// the step against the document as it was before it rather than stacking a
/// step per frame. So the card still works on it afterwards, Escape is one
/// undo, and the journal names the number the person stopped at rather than
/// the sixty they passed through.
///
/// Everything here is arithmetic over numbers a test can hand it, the same
/// bargain `transform_modal.dart` struck.
library;

import 'dart:math' as math;

/// Which operation is being dragged, and what its one number is called.
///
/// **A table rather than a field on `ModelCommand`.** A command knows its own
/// arguments and their hints; what it does not know, and should not, is which
/// of them a drag across the screen means — that is a decision about this
/// application's pointer, not about the document.
enum DraggedValue {
  extrude('mesh.extrude', 'distance', 'Extrude'),
  bevel('mesh.bevel', 'width', 'Bevel'),
  // `ux-39`: both are a single number a pointer means, the same as the
  // two above — an inset's thickness and how far along its rail a loop
  // travels.
  inset('mesh.inset', 'thickness', 'Inset'),
  slide('mesh.slide', 'amount', 'Slide');

  const DraggedValue(this.tool, this.argument, this.label);

  /// The rail id this is armed by.
  final String tool;

  /// The command argument the pointer moves — the key in its own
  /// `arguments`/`toJson`, so amending goes through the command's own JSON
  /// exactly as the operation card does.
  final String argument;

  /// What the readout beside the pointer calls it.
  final String label;

  /// The one this [tool] asks for, or null where the tool is not one of
  /// these — which is every tool the ordinary drag machinery already owns.
  static DraggedValue? forTool(String? tool) {
    for (final DraggedValue each in DraggedValue.values) {
      if (each.tool == tool) return each;
    }
    return null;
  }
}

/// One of those drags, in progress.
final class ValueDrag {
  ValueDrag({required this.what, required this.started, required this.perPixel})
    : amount = started;

  final DraggedValue what;

  /// What the operation landed at before anybody moved — `stepOf`'s own
  /// guess. A drag is measured from here, so letting go without moving
  /// leaves exactly what pressing the key has always left.
  final double started;

  /// How much one logical pixel of travel is worth, in the model's own
  /// units. Read from the same pixel size the overlay uses, so the face
  /// follows the pointer rather than lagging behind it.
  final double perPixel;

  /// Where it is now.
  double amount;

  /// What has been typed since the drag opened, if anything — the same
  /// "type a number instead of aiming at it" `TransformModal` offers.
  String typed = '';

  /// Whether the amount snaps to a grid — Control, as everywhere else.
  bool snapping = false;

  /// The grid it snaps to. The person's own, handed in by the session from
  /// Settings, so one number answers for a move and for an extrusion.
  double snapStep = 0.1;

  /// Moves the amount by [pixels] of travel.
  ///
  /// **Rightward is more**, which is the direction every value slider in
  /// this application already grows in, and up is more as well: a face being
  /// pulled out of a model is more often dragged away from the body than
  /// along the screen, and a drag that only read one axis would sit still
  /// for half the gestures people make. The two are added rather than
  /// measured as a distance, so pulling back undoes exactly what pulling out
  /// did instead of growing whichever way the hand went.
  void dragged(double dx, double dy, {double fine = 1.0}) {
    if (typed.isNotEmpty) return;
    amount += (dx - dy) * perPixel * fine;
  }

  /// A character typed while the drag is open. Answers whether it was taken.
  ///
  /// Digits, a decimal point and a leading minus — the same set
  /// `TransformModal` takes, and for the same reason: anything else is a key
  /// that still means whatever it means.
  bool typedCharacter(String character) {
    if (character == '-' && typed.isEmpty) {
      typed = '-';
      return true;
    }
    if (character == '.' || character == ',') {
      if (typed.contains('.')) return true;
      typed = '${typed.isEmpty ? '0' : typed}.';
      return true;
    }
    if (character.length != 1) return false;
    final int code = character.codeUnitAt(0);
    if (code < 0x30 || code > 0x39) return false;
    typed += character;
    return true;
  }

  /// Takes back the last typed character. Answers whether there was one.
  bool backspace() {
    if (typed.isEmpty) return false;
    typed = typed.substring(0, typed.length - 1);
    return true;
  }

  /// The number the operation should be run with right now.
  ///
  /// A typed number wins outright — somebody who has typed 0.25 has said what
  /// they want, and a pointer that keeps moving under their hand must not
  /// argue with it.
  double get value {
    if (typed.isNotEmpty) {
      final double? said = double.tryParse(typed);
      if (said != null) return said;
    }
    if (!snapping || snapStep <= 0) return amount;
    return (amount / snapStep).roundToDouble() * snapStep;
  }

  /// "Extrude · 0.35 m" — what goes beside the pointer, the same shape
  /// `ux-11`'s own readout takes.
  String get readout {
    final double now = value;
    final String number = typed.isNotEmpty
        ? typed
        : now.abs() >= 10
        ? now.toStringAsFixed(1)
        : now.toStringAsFixed(3);
    return '${what.label} · $number m';
  }

  /// The keys worth naming while this is open, in the one string
  /// `TransformReadout` draws as chips — the same shape `TransformModal.hints`
  /// answers in, so the label beside the pointer needs no second branch.
  String get hints => <String>[
    if (typed.isEmpty) 'Ctrl snaps ${_trimmed(snapStep)}' else 'Backspace',
    'Shift precise',
    'Esc cancels',
  ].join(' · ');

  static String _trimmed(double it) {
    final String said = it.toStringAsFixed(3);
    final String cut = said.replaceFirst(RegExp(r'0+$'), '');
    return cut.endsWith('.') ? cut.substring(0, cut.length - 1) : cut;
  }

  /// How much one pixel is worth for a model whose selection sits [distance]
  /// from the eye, given the overlay's own [pixel] size at unit distance.
  ///
  /// The same conversion a modal move makes, and deliberately so: a face
  /// extruded a centimetre and a vertex moved a centimetre should take the
  /// same hand movement, or the two feel like different applications.
  static double perPixelAt({
    required double pixel,
    required double distance,
    bool perspective = true,
  }) => math.max(pixel * (perspective ? distance : 1.0), 1e-9);
}
