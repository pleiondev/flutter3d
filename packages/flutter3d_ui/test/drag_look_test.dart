/// Looking around by dragging, where there is no pointer to lock.
///
///     flutter test test/drag_look_test.dart
///
/// Two games had written this out, identically.
library;

import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('motion with nothing down is not a player looking anywhere', () {
    // A mouse crossing the window on the web, where the pointer has not been
    // clicked into yet.
    final look = DragLook()..moved(const Offset(40.0, 40.0));

    expect(look.take(), Vector2.zero());
  });

  test('and a drag adds up until somebody takes it', () {
    // **Taken rather than read, and this is why it cannot go through
    // `InputState`:** `endStep` clears that at the end of every simulation
    // step, so on a frame where the loop ran twice — or not at all — the camera
    // would find the motion already thrown away.
    final look = DragLook()..begin();

    look
      ..moved(const Offset(3.0, 1.0))
      ..moved(const Offset(4.0, -2.0));

    expect(look.take(), Vector2(7.0, -1.0));
    expect(look.take(), Vector2.zero(), reason: 'it was handed out twice');
  });

  test('and draining into a vector is the same answer', () {
    final look = DragLook()
      ..begin()
      ..moved(const Offset(2.0, 5.0));
    final out = Vector3.zero().xy;

    look.drainInto(out);

    expect(out, Vector2(2.0, 5.0));
    expect(look.take(), Vector2.zero());
  });

  test('and letting go stops the turn', () {
    final look = DragLook()
      ..begin()
      ..end()
      ..moved(const Offset(9.0, 9.0));

    expect(look.take(), Vector2.zero());
    expect(look.isDragging, isFalse);
  });

  test('and a cancelled pointer is a drag that ended', () {
    // A notification sliding over the window takes the pointer away without an
    // "up". A game that listened only for "up" kept turning underneath it.
    final look = DragLook()..begin();
    expect(look.isDragging, isTrue);

    look.end();

    expect(look.isDragging, isFalse);
  });
}
