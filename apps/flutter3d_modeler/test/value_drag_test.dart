/// `ux-29`'s own number: what a drag across the screen is worth to an
/// extrusion, and what typing one instead does.
///
///     flutter test test/value_drag_test.dart
///
/// Arithmetic over numbers a test hands it, the same bargain
/// `transform_modal_test.dart` already keeps — what needs a window is the key
/// that arrives and the pointer that moves, and that is the session's half.
library;

import 'package:flutter3d_modeler/src/value_drag.dart';
import 'package:flutter_test/flutter_test.dart';

ValueDrag _drag({double started = 0.1, double perPixel = 0.01}) =>
    ValueDrag(what: DraggedValue.extrude, started: started, perPixel: perPixel);

void main() {
  group('ux-29: which operations follow the pointer', () {
    test('the two the row names, and nothing else', () {
      expect(DraggedValue.forTool('mesh.extrude'), DraggedValue.extrude);
      expect(DraggedValue.forTool('mesh.bevel'), DraggedValue.bevel);
      // Mutation: answer for every mesh tool. Triangulate and Merge take no
      // number at all, so the pointer would drive an argument that is not
      // there and the operation would be amended into nothing.
      expect(DraggedValue.forTool('mesh.triangulate'), isNull);
      expect(DraggedValue.forTool(null), isNull);
    });

    test('each names the argument its own command calls the number', () {
      // Mutation: one name for both. `BevelEdges` calls it `width` and
      // `Extrude` calls it `distance`; amending through the wrong key adds a
      // field the command's own `fromJson` ignores, so the drag moves
      // nothing and nothing says why.
      expect(DraggedValue.extrude.argument, 'distance');
      expect(DraggedValue.bevel.argument, 'width');
    });
  });

  group('ux-29: what the drag is worth', () {
    test('it starts at whatever the operation guessed', () {
      expect(_drag(started: 0.25).value, 0.25);
    });

    test('rightward and upward are both more', () {
      final ValueDrag right = _drag()..dragged(50, 0);
      final ValueDrag up = _drag()..dragged(0, -50);

      // Mutation: read the horizontal travel alone. A face pulled away from
      // the body — which is the direction most extrusions are dragged in —
      // then sits still while the hand moves.
      expect(right.value, closeTo(0.6, 1e-9));
      expect(up.value, closeTo(0.6, 1e-9));
    });

    test('and pulling back undoes exactly what pulling out did', () {
      final ValueDrag drag = _drag()
        ..dragged(50, 0)
        ..dragged(-50, 0);

      // Mutation: accumulate the distance rather than the signed sum. The
      // number then only ever grows, and a hand that overshot has no way
      // back short of typing.
      expect(drag.value, closeTo(0.1, 1e-9));
    });

    test('Shift is a tenth of the travel', () {
      final ValueDrag drag = _drag()..dragged(50, 0, fine: 0.1);
      expect(drag.value, closeTo(0.15, 1e-9));
    });

    test('Control rounds it to the person\'s own step', () {
      final ValueDrag drag = _drag()
        ..dragged(43, 0)
        ..snapStep = 0.25
        ..snapping = true;

      // 0.1 + 0.43 = 0.53, which rounds to half.
      expect(drag.value, closeTo(0.5, 1e-9));
      drag.snapping = false;
      expect(drag.value, closeTo(0.53, 1e-9));
    });
  });

  group('ux-29: typing a number instead of aiming at it', () {
    test('a typed number wins over the pointer', () {
      final ValueDrag drag = _drag()..dragged(50, 0);
      expect(drag.typedCharacter('2'), isTrue);

      // Mutation: let the pointer keep moving the number. Somebody who has
      // typed 2 has said what they want, and a hand that has not left the
      // mouse yet then argues with them.
      drag.dragged(500, 0);
      expect(drag.value, 2.0);
    });

    test('digits, a point and a leading minus, and nothing else', () {
      final ValueDrag drag = _drag();
      expect(drag.typedCharacter('-'), isTrue);
      expect(drag.typedCharacter('0'), isTrue);
      expect(drag.typedCharacter('.'), isTrue);
      expect(drag.typedCharacter('5'), isTrue);
      expect(drag.value, -0.5);

      // A second point is taken and changes nothing, rather than landing in
      // the string and making it unparseable.
      expect(drag.typedCharacter('.'), isTrue);
      expect(drag.value, -0.5);
      // Anything else is a key that still means whatever it means.
      expect(drag.typedCharacter('x'), isFalse);
    });

    test('backspace takes one back, and says when there is none', () {
      final ValueDrag drag = _drag();
      drag.typedCharacter('7');

      expect(drag.backspace(), isTrue);
      expect(drag.typed, isEmpty);
      // Mutation: answer true either way. Backspace inside a drag with
      // nothing typed then swallows the key rather than letting it mean what
      // it means elsewhere.
      expect(drag.backspace(), isFalse);
    });

    test('and with the typing cleared the pointer has it back', () {
      final ValueDrag drag = _drag()..dragged(50, 0);
      drag
        ..typedCharacter('2')
        ..backspace();

      expect(drag.value, closeTo(0.6, 1e-9));
    });
  });

  group('ux-29: what it says beside the pointer', () {
    test('the operation and the number', () {
      expect(_drag(started: 0.35).readout, 'Extrude · 0.350 m');
      expect(
        ValueDrag(
          what: DraggedValue.bevel,
          started: 0.02,
          perPixel: 0.01,
        ).readout,
        'Bevel · 0.020 m',
      );
    });

    test('a typed number is shown as typed, half-written', () {
      final ValueDrag drag = _drag();
      drag
        ..typedCharacter('0')
        ..typedCharacter('.');

      // Mutation: format the parsed value. "0." reads back as 0 and the
      // person watching the label sees their own keystroke vanish.
      expect(drag.readout, 'Extrude · 0. m');
    });

    test('the hints name the step the modifier would round to', () {
      final ValueDrag drag = _drag()..snapStep = 0.25;
      expect(drag.hints, contains('0.25'));
      expect(drag.hints, contains('Esc'));

      drag.typedCharacter('1');
      expect(drag.hints, contains('Backspace'));
    });
  });

  test('ux-29: a pixel is worth more further away', () {
    final double near = ValueDrag.perPixelAt(pixel: 0.001, distance: 1);
    final double far = ValueDrag.perPixelAt(pixel: 0.001, distance: 10);

    // Mutation: use the pixel size alone. An extrusion on a model the camera
    // has pulled back from then crawls, and one up close runs away — the
    // same complaint a move had before it measured a pixel at the depth the
    // selection is at.
    expect(far, greaterThan(near));
    // An orthographic camera has no depth to scale by.
    expect(
      ValueDrag.perPixelAt(pixel: 0.001, distance: 10, perspective: false),
      0.001,
    );
  });
}
