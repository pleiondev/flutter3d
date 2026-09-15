/// `tut-08`: a real "Import" action in the app's own toolbar, merging a
/// second file into the document already open through `ImportInto` — rather
/// than only reachable through `ModelSession.import` over MCP.
///
///     flutter test test/file_import_test.dart
///
/// **The native file dialog stands in for a person's own click**, through a
/// fake `FileSelectorPlatform` — the exact pattern
/// `apps/flutter3d_editor/test/timeline_attach_screen_test.dart` already
/// uses for its own save panel, `FileSelectorPlatform.instance` being the
/// platform interface's own seam for a test to stand behind.
///
/// **The fake hands back an in-memory `XFile.fromData`, not a real file on
/// disk.** `dart:io`'s own `File.readAsBytes` needs the real event loop
/// `tester.runAsync` opens, and this application's own live viewport keeps
/// scheduling real frames of its own throughout a test the way
/// `file_drop_io_test.dart`'s own doc comment already describes — so a real
/// file read raced against that never reliably lands inside a test's own
/// fixed run time. `XFile.fromData`'s own `readAsBytes` resolves from memory
/// on a plain microtask instead, which is both simpler and deterministic.
library;

import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vector_math/vector_math.dart';

/// A picker that never opens a real dialog — it hands back an in-memory
/// [XFile] built from [bytes]/[name], the way a person choosing a real file
/// in a real dialog would end up handing `openModel` the same two things.
final class _FakeOpenFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeOpenFileSelector(this.bytes, this.name);

  final Uint8List bytes;
  final String name;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(bytes, path: name);
}

/// Answers every read with nothing and every write as if it landed —
/// `ModelerScreen`'s own autosave writes through this during the test
/// instead of reaching for a real file or IndexedDB.
final class _NullBinaryStorage implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}

/// A one-object document, encoded as a real `.f3d` file — the format
/// `_ModelerScreenState._importFile` and `_openFile` alike decode through
/// `decodeBytes`, exactly as a person's own file would be.
Uint8List _f3dBytesNamed(String objectName) {
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: objectName,
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  return F3dWriter(toModelDocument(project)).write();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = _NullBinaryStorage();
  late FileSelectorPlatform previousSelector;

  setUp(() {
    previousSelector = FileSelectorPlatform.instance;
  });
  tearDown(() {
    FileSelectorPlatform.instance = previousSelector;
  });

  /// Starts [ModelerScreen] and waits for the startup document (one cube) to
  /// be on screen — the same shape `file_drop_io_test.dart`'s own tut-17
  /// group already waits through, `openDevice()`'s own real async work
  /// included.
  Future<void> pumpReady(WidgetTester tester) async {
    // Wide enough for `LayoutClass.desktop` — `ui-05`'s own 1200-pixel
    // boundary — since the outliner rows this file reads are `ModelerShell`'s
    // own, and the narrower tablet and phone shells draw them behind a
    // sheet this test never opens.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ModelerScreen(autosaveStorage: storage)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('cube'), findsWidgets);
  }

  /// Taps the toolbar's own [buttonText] ("Open" or "Import"), lets the
  /// picker and the decode run, then confirms the import screen's own
  /// dialog with its default choices — the same unit/axis/cleanup screen
  /// both buttons share.
  ///
  /// **Explicit pumps, never `pumpAndSettle`.** The live viewport this
  /// screen draws keeps scheduling frames of its own — a real orbit camera
  /// and render loop under a full `ModelerScreen`, not a static widget — so
  /// `pumpAndSettle` never sees "nothing scheduled" and hangs forever;
  /// `file_drop_io_test.dart`'s own tut-17 group already avoids it for the
  /// identical reason.
  Future<void> importThrough(WidgetTester tester, String buttonText) async {
    await tester.tap(find.widgetWithText(TextButton, buttonText));
    // The picker and the decode both resolve from memory (no real IO, see
    // the library doc comment), so plain pumps drain them without needing
    // `runAsync` at all — a few, since each only drains one microtask hop
    // of the awaited chain.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    // The import screen's own dialog entrance transition.
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Import merges a second file\'s objects into the currently open '
      'project without discarding what was already there', (
    WidgetTester tester,
  ) async {
    FileSelectorPlatform.instance = _FakeOpenFileSelector(
      _f3dBytesNamed('second-object'),
      'second.f3d',
    );

    await pumpReady(tester);
    await importThrough(tester, 'Import');

    // Mutation: land `ReplaceDocument` over the *incoming* project alone
    // instead of `importInto`'s own merged one — this would read the
    // startup cube gone rather than still on screen beside the import.
    expect(find.text('cube'), findsWidgets);
    expect(find.text('second-object'), findsOneWidget);
    // The document name still names the project a person has been editing,
    // not the file Import just brought in — `_installOpened` is what
    // renames it, and this action never calls that.
    expect(find.text('second.f3d'), findsNothing);
  });

  testWidgets('Open still fully replaces the document, unlike Import', (
    WidgetTester tester,
  ) async {
    FileSelectorPlatform.instance = _FakeOpenFileSelector(
      _f3dBytesNamed('replacement-object'),
      'replacement.f3d',
    );

    await pumpReady(tester);
    await importThrough(tester, 'Open');

    // Mutation: route Open through the same merge Import now uses instead
    // of `_installOpened`'s wholesale replacement — this would read the
    // startup cube still present alongside the opened file.
    expect(find.text('cube'), findsNothing);
    expect(find.text('replacement-object'), findsOneWidget);
    expect(find.text('replacement.f3d'), findsOneWidget);
  });
}
