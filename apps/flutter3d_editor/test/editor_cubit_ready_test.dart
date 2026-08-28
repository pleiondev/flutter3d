/// What happens to an open document's state: the message, the axis, the
/// lamp, hidden types, and what the palette is holding.
///
///     flutter test test/editor_cubit_ready_test.dart
///
/// See `editor_cubit_test.dart` for how a document gets to this state at all,
/// and for why this is a plain `test()` and not a widget test.
library;

import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/gizmos.dart';
import 'package:flutter3d_editor/src/palette_items.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_cubit_helpers.dart';

void main() {
  group('once a document is open', () {
    late EditorCubit cubit;
    late Editing editing;

    setUp(() {
      editing = openTestDocument();
      cubit = EditorCubit()..opened(editing, assetRoot: null, looks: noLooks);
    });

    test('say updates the message and nothing else', () {
      cubit.say('deleted');
      final state = cubit.state as EditorReady;
      expect(state.said, 'deleted');
      expect(state.editing, same(editing));
    });

    test('a message before anything is open does nothing', () {
      final fresh = EditorCubit()..say('too early');
      expect(fresh.state, isA<EditorOpening>());
    });

    test('setAxis changes the axis and leaves the message alone', () {
      cubit.say('at 1.00, 0.00, 0.00');
      cubit.setAxis(EditorAxis.z);
      final state = cubit.state as EditorReady;
      expect(state.axis, EditorAxis.z);
      expect(state.said, 'at 1.00, 0.00, 0.00');
    });

    test('toggleLamp flips it, says so, and returns the new value', () {
      final on = cubit.toggleLamp();
      expect(on, isFalse);
      var state = cubit.state as EditorReady;
      expect(state.lampOn, isFalse);
      expect(state.said, contains('off'));

      final onAgain = cubit.toggleLamp();
      expect(onAgain, isTrue);
      state = cubit.state as EditorReady;
      expect(state.lampOn, isTrue);
      expect(state.said, contains('on'));
    });

    test('toggleHidden hides a type, and hides it again to show it', () {
      cubit.toggleHidden('monster', label: 'monster');
      var state = cubit.state as EditorReady;
      expect(state.hidden, <String>{'monster'});
      expect(state.said, contains('hidden'));

      cubit.toggleHidden('monster', label: 'monster');
      state = cubit.state as EditorReady;
      expect(state.hidden, isEmpty);
      expect(state.said, contains('shown'));
    });

    test('setPlacing arms the palette, and null puts it down', () {
      final row = Placeable(
        kind: Piece.brush,
        what: 'stone',
        count: 2,
        tint: Vector3(1.0, 1.0, 1.0),
      );
      cubit.setPlacing(row);
      var state = cubit.state as EditorReady;
      expect(state.placing, same(row));
      expect(state.said, contains('stone'));

      cubit.setPlacing(null);
      state = cubit.state as EditorReady;
      expect(state.placing, isNull);
      expect(state.said, 'nothing to place');
    });
  });
}
