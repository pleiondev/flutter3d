/// `tpl-01`'s own mechanism: read one of the editor's own templates straight
/// off disk (no `rootBundle`, no Flutter SDK) and hand it to
/// `flutter3d_editor_core`'s already-tested [scaffold] — the exact function
/// the editor's own "new project" wizard already calls
/// (`apps/flutter3d_editor/lib/main.dart`). Nothing here decides what a
/// template contains; that stays where the wizard and its own
/// `templates_test.dart` already hold it honest.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

/// Where the four templates this repository ships actually live — the
/// editor's own asset directory, read as plain files rather than as a bundle.
String defaultTemplatesRoot(String repositoryRoot) =>
    '$repositoryRoot/apps/flutter3d_editor/assets/templates';

/// The genres [templatesRoot]'s `index.json` names, in the order it names
/// them — what `--list` prints.
List<String> availableTemplates(String templatesRoot) {
  final index =
      jsonDecode(File('$templatesRoot/index.json').readAsStringSync())
          as Map<String, Object?>;
  return (index['templates']! as List<Object?>).cast<String>();
}

/// Reads one template's manifest and every file its manifest lists, then
/// writes [scaffold]'s answer under [targetDirectory] — the whole of what
/// `dart run flutter3d:init --template=<genre>` would do, once `ap-10` gives
/// it that name.
///
/// [projectName] defaults to [targetDirectory]'s own last path segment,
/// through [packageName] — the same default the editor's wizard uses when a
/// person has not typed one.
void writeProject({
  required String templatesRoot,
  required String genre,
  required String targetDirectory,
  String? projectName,
}) {
  final where = '$templatesRoot/$genre';
  final manifestFile = File('$where/index.json');
  if (!manifestFile.existsSync()) {
    throw ArgumentError.value(
      genre,
      'genre',
      'no such template under $templatesRoot — known: '
          '${availableTemplates(templatesRoot).join(', ')}',
    );
  }

  final template = Template.parse(genre, manifestFile.readAsStringSync());
  final sources = <String, Uint8List>{
    for (final name in template.files.keys)
      name: File('$where/$name').readAsBytesSync(),
  };

  final name =
      projectName ?? targetDirectory.split(Platform.pathSeparator).last;
  final project = scaffold(template: template, project: name, sources: sources);

  for (final entry in project.entries) {
    final file = File('$targetDirectory/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.value);
  }
}
