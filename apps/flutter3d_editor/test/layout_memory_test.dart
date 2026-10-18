/// Where somebody left the panels, kept for their next launch.
///
///     flutter test test/layout_memory_test.dart
library;

import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_editor/src/layout_memory.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Documents in a map, which is what [Storage] is an interface for.
final class _Documents extends Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  test('a layout written is the layout read on the next launch', () async {
    // Mutation: have `write` store `const DockArrangement().toJson()`. The
    // bottom strip comes back at its default height and the left side open.
    final storage = _Documents();
    await LayoutMemory(storage: storage).write(
      const DockArrangement()
          .withSize(DockSide.bottom, 330)
          .withCollapsed(DockSide.left, folded: true),
    );

    final read = await LayoutMemory(storage: storage).read();

    expect(read.sizeOf(DockSide.bottom), 330);
    expect(read.isCollapsed(DockSide.left), isTrue);
  });

  test('a first launch, or a file that lost a brace, is the default', () async {
    // Mutation: drop the `on FormatException` catch. The broken file throws
    // and the editor would not open over a convenience file.
    final storage = _Documents();
    expect((await LayoutMemory(storage: storage).read()).collapsed, isEmpty);

    storage.documents['layout.json'] = '{"sizes": {';
    expect((await LayoutMemory(storage: storage).read()).collapsed, isEmpty);
  });
}
