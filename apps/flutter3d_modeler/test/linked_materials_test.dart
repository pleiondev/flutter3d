/// `ux-47`: a linked `.fmat` that changes on disk reaches the viewport.
///
///     flutter test test/linked_materials_test.dart
///
/// **Against a host that is two functions, not against a filesystem.** What
/// goes wrong here is not "can `dart:io` watch a file" — it can — but which
/// files are watched, what a change runs, and what a half-written save
/// leaves behind. All three are answerable with a stream a test controls.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart'
    show MaterialDocument, SurfaceMaterial, writeFmat;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/files/linked_materials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

/// A project whose materials link to the paths given.
ModelProject _linkedTo(List<String?> paths) => const ModelProject().copyWith(
  materials: <ProjectMaterial>[
    for (var i = 0; i < paths.length; i++)
      ProjectMaterial(
        surface: SurfaceMaterial(name: 'material $i'),
        fmat: paths[i],
      ),
  ],
);

/// A `.fmat` naming a base colour, as bytes.
Uint8List _fmat(Vector4 colour) => Uint8List.fromList(
  utf8.encode(
    writeFmat(
      MaterialDocument(
        surface: SurfaceMaterial(name: 'oak', baseColor: colour),
      ),
    ),
  ),
);

/// A host whose watch stream a test fires by hand.
final class _Fake {
  final Map<String, StreamController<void>> streams =
      <String, StreamController<void>>{};
  final Map<String, Uint8List?> files = <String, Uint8List?>{};
  final List<String> opened = <String>[];

  LinkedMaterialHost get host => (
    watch: (String path) =>
        (streams[path] ??= StreamController<void>.broadcast()).stream,
    read: (String path) async => files[path],
    openInEditor: (String path) async {
      opened.add(path);
      return true;
    },
  );

  /// Says the file at [path] changed, and lets the read settle.
  Future<void> changed(String path) async {
    streams[path]!.add(null);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    for (final StreamController<void> each in streams.values) {
      await each.close();
    }
  }
}

void main() {
  group('which files are watched', () {
    test('exactly the ones the project links to, each once', () {
      final fake = _Fake();
      final watcher = LinkedMaterials(host: fake.host, onRelink: (_) {});
      addTearDown(watcher.dispose);
      addTearDown(fake.close);

      // Two materials over one file is the ordinary case for a library, and
      // one watch is what that should cost.
      watcher.follow(_linkedTo(<String?>['oak.fmat', 'oak.fmat', null]));

      expect(watcher.watching, <String>['oak.fmat']);
    });

    test('and a project that stops linking one stops watching it', () async {
      final fake = _Fake();
      final watcher = LinkedMaterials(host: fake.host, onRelink: (_) {});
      addTearDown(watcher.dispose);
      addTearDown(fake.close);

      watcher.follow(_linkedTo(<String?>['oak.fmat', 'steel.fmat']));
      expect(watcher.watching.toSet(), <String>{'oak.fmat', 'steel.fmat'});

      // Mutation: only ever add. A session that opens ten projects then
      // holds ten projects' worth of watches, firing commands against
      // material indices that belong to a document nobody has open.
      watcher.follow(_linkedTo(<String?>['steel.fmat']));
      expect(watcher.watching, <String>['steel.fmat']);
    });

    test('a path of nothing but spaces is not a path', () {
      final fake = _Fake();
      final watcher = LinkedMaterials(host: fake.host, onRelink: (_) {});
      addTearDown(watcher.dispose);

      watcher.follow(_linkedTo(<String?>['  ', '']));
      expect(watcher.watching, isEmpty);
    });
  });

  group('what a change runs', () {
    test(
      'a re-link per material over that file, carrying the new bytes',
      () async {
        final fake = _Fake()
          ..files['oak.fmat'] = _fmat(Vector4(0.2, 0.6, 0.1, 1.0));
        final relinks = <LinkMaterialFile>[];
        final watcher = LinkedMaterials(host: fake.host, onRelink: relinks.add);
        addTearDown(watcher.dispose);
        addTearDown(fake.close);

        watcher.follow(
          _linkedTo(<String?>['oak.fmat', 'steel.fmat', 'oak.fmat']),
        );
        await fake.changed('oak.fmat');

        // **A command, not a direct write.** It goes through `ModelHistory`
        // like every other edit, so a file changing behind the editor is one
        // undo step that says what it was — and the rows that share the file
        // both move.
        expect(relinks.map((LinkMaterialFile it) => it.index), <int>[0, 2]);
        expect(relinks.first.path, 'oak.fmat');
        expect(relinks.first.bytes, isNotNull);
      },
    );

    test('and the command really changes the colour', () async {
      final fake = _Fake()
        ..files['oak.fmat'] = _fmat(Vector4(0.9, 0.1, 0.1, 1.0));
      final relinks = <LinkMaterialFile>[];
      final watcher = LinkedMaterials(host: fake.host, onRelink: relinks.add);
      addTearDown(watcher.dispose);
      addTearDown(fake.close);

      final ModelProject project = _linkedTo(<String?>['oak.fmat']);
      watcher.follow(project);
      await fake.changed('oak.fmat');

      // The row's own acceptance, minus the frame: editing a linked file's
      // base colour reaches the document.
      final ModelHistory history = ModelHistory(project);
      expect(history.run(relinks.single), isNull);
      expect(
        history.project.materials.single.surface.baseColor.x,
        // `Vector4` holds 32-bit floats, and a `.fmat` is written and read
        // as text: 0.9 comes back as the nearest float to it.
        closeTo(0.9, 1e-6),
      );
    });

    test('a file that will not read keeps the last good material', () async {
      final fake = _Fake()
        ..files['oak.fmat'] = Uint8List.fromList(<int>[1, 2, 3]);
      final relinks = <LinkMaterialFile>[];
      final trouble = <String>[];
      final watcher = LinkedMaterials(
        host: fake.host,
        onRelink: relinks.add,
        onTrouble: (String path, String because) =>
            trouble.add('$path $because'),
      );
      addTearDown(watcher.dispose);
      addTearDown(fake.close);

      final ModelProject project = _linkedTo(<String?>['oak.fmat']);
      watcher.follow(project);
      await fake.changed('oak.fmat');

      // **A `.fmat` spends part of every save half-written**, so the
      // command itself is what refuses — it already does, with the reason —
      // and the material keeps the look it had.
      final ModelHistory history = ModelHistory(project);
      final String? refused = history.run(relinks.single);
      expect(refused, isNotNull);
      expect(refused, contains('oak.fmat'));
      expect(history.project.materials.single.surface.name, 'material 0');
    });

    test('a file that has gone says so and runs nothing', () async {
      final fake = _Fake();
      final relinks = <LinkMaterialFile>[];
      final trouble = <String>[];
      final watcher = LinkedMaterials(
        host: fake.host,
        onRelink: relinks.add,
        onTrouble: (String path, String because) =>
            trouble.add('$path: $because'),
      );
      addTearDown(watcher.dispose);
      addTearDown(fake.close);

      watcher.follow(_linkedTo(<String?>['gone.fmat']));
      await fake.changed('gone.fmat');

      expect(relinks, isEmpty);
      expect(trouble.single, contains('gone.fmat'));
    });
  });

  test('openInEditor hands the path to the platform', () async {
    final fake = _Fake();
    final watcher = LinkedMaterials(host: fake.host, onRelink: (_) {});
    addTearDown(watcher.dispose);

    expect(await watcher.openInEditor('oak.fmat'), isTrue);
    expect(fake.opened, <String>['oak.fmat']);
  });
}
