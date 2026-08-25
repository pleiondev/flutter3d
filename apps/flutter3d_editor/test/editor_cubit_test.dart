/// Which screen the editor shows: opening, choosing a template, open, or
/// failed.
///
///     flutter test test/editor_cubit_test.dart
///
/// **Reachable from a plain `test()`, which is the point of using a cubit at
/// all** — see `EditorCubit`'s own doc comment, and `documents.dart`'s: "the
/// parts that can lose somebody's work... need no window and are tested
/// without one." Nothing here opens a file or a device; every document is a
/// string parsed in memory, the way `editing_test.dart` already does it.
///
/// What happens once a document is open and being edited is
/// `editor_cubit_ready_test.dart` — a large enough state machine of its own to
/// want the room.
library;

import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

void main() {
  group('before anything is known', () {
    test('the cubit says so', () {
      expect(EditorCubit().state, isA<EditorOpening>());
    });
  });

  group('nothing at the path', () {
    test('offers the templates, and says where it looked', () {
      final cubit = EditorCubit()
        ..nothingFound(<Template>[testTemplate], path: '/levels/first.json');

      final state = cubit.state;
      expect(state, isA<EditorChoosing>());
      state as EditorChoosing;
      expect(state.templates, <Template>[testTemplate]);
      expect(state.said, contains('/levels/first.json'));
    });

    test('and a failed create says why without leaving the chooser', () {
      final cubit = EditorCubit()
        ..nothingFound(<Template>[testTemplate], path: '/levels/first.json')
        ..choosingSaid('/levels is not empty');

      final state = cubit.state;
      expect(state, isA<EditorChoosing>());
      state as EditorChoosing;
      expect(state.said, '/levels is not empty');
      // The offer itself survives the failure — a person can still pick a
      // template after being told the first attempt did not work.
      expect(state.templates, <Template>[testTemplate]);
    });

    test('and a message before there is a chooser at all does nothing', () {
      final cubit = EditorCubit()..choosingSaid('too early');
      expect(cubit.state, isA<EditorOpening>());
    });
  });

  group('a document opens', () {
    test('and says how many brushes, when this editor may save it', () {
      final editing = openTestDocument();
      final cubit = EditorCubit()
        ..opened(editing, assetRoot: null, looks: noLooks);

      final state = cubit.state;
      expect(state, isA<EditorReady>());
      state as EditorReady;
      expect(state.editing, same(editing));
      expect(state.said, 'opened 2 brushes');
      expect(state.assetRoot, isNull);
      expect(state.axis, EditorAxis.x);
      expect(state.lampOn, isTrue);
      expect(state.hidden, isEmpty);
      expect(state.placing, isNull);
    });

    test('and names the generator when this editor may not', () {
      final editing = openTestDocument(generatedBy: 'tool/make_crypt.py');
      final cubit = EditorCubit()
        ..opened(editing, assetRoot: null, looks: noLooks);

      final state = cubit.state as EditorReady;
      expect(state.said, contains('written by tool/make_crypt.py'));
    });
  });

  group('nothing could be opened', () {
    test('says why, from any state', () {
      final cubit = EditorCubit()
        ..nothingFound(<Template>[testTemplate], path: '/levels/first.json')
        ..failed(StateError('no device'));

      expect(cubit.state, isA<EditorFailed>());
      expect((cubit.state as EditorFailed).error, isA<StateError>());
    });
  });
}
