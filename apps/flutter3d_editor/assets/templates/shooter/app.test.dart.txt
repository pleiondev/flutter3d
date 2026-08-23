/// The level this project ships, read the way the game reads it.
///
///     flutter test
///
/// **This file is the one a new project starts with**, copied into it by the
/// editor's scaffolder — which is why it is here rather than being a string in
/// `apps/flutter3d_editor/lib/src/scaffold.dart`. A test that only ever exists as text
/// is one that stops compiling six months later and nobody finds out until
/// somebody creates a project, which is the same argument `main.dart` next
/// door already makes about itself.
///
/// It is also `apps/flutter3d_template_app`'s only test, and until now this application
/// had none — the one application in the repository whose whole job is to be
/// copied.
///
/// **Named `widget_test.dart` on purpose.** `flutter create` writes one of
/// those, referring to an application class that does not exist here, into any
/// project that does not already have a file by that name — and a new project
/// would then fail `flutter analyze` immediately after the two commands its
/// README gives. Taking the name is the only thing that stops it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final text = File('assets/levels/first.json').readAsStringSync();
  final level = Level.fromJson(jsonDecode(text) as Map<String, Object?>);

  test('the level is a document this engine understands', () {
    // A level is a document and a document can be wrong. Asking here is the
    // difference between finding out in a second and finding out in a window.
    expect(level.brushes, isNotEmpty, reason: 'nothing to stand on');
    expect(level.entities.where((EntityDef it) => it.type.contains('spawn')),
        hasLength(1), reason: 'a level starts somewhere, exactly once');
  });

  final editorLooks = File('assets/editor.json');

  test('and every model it names is a file that is really there', () {
    // A path with a typo draws nothing and says nothing.
    final looks =
        jsonDecode(editorLooks.readAsStringSync()) as Map<String, Object?>;
    for (final entry in looks.entries) {
      final described = entry.value;
      if (described is! Map<String, Object?>) continue;
      final model = described['model'];
      if (model is! String) continue;
      expect(File(model).existsSync(), isTrue,
          reason: '${entry.key} names $model, which is not there');
    }
    // **Skipped in `apps/flutter3d_template_app` and not in a project made from it**,
    // which is the honest shape: the looks and the models a project draws with
    // come from the template it was made from, and this application is what is
    // left when you take those away. Written as a skip rather than an early
    // return so that a run says which of the two it is looking at.
  }, skip: editorLooks.existsSync()
      ? false
      : 'no assets/editor.json here: the template supplies the looks and the '
          'models, and this is the application without them');
}
