/// `AutosaveController`: the timer that turns `doc-17`'s pure `shouldSave`
/// into an actual write, driven at test speed rather than a wall clock.
///
///     flutter test test/autosaving_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/autosaving.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A storage kept in memory, counting every attempt so a test can ask how
/// many actually happened rather than only whether the document is there.
final class FakeBinaryStorage implements BinaryStorage {
  final Map<String, Uint8List> documents = <String, Uint8List>{};
  int writeCount = 0;
  bool refuse = false;

  @override
  Future<Uint8List?> read(String name) async => documents[name];

  @override
  Future<bool> write(String name, Uint8List contents) async {
    writeCount++;
    if (refuse) return false;
    documents[name] = contents;
    return true;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(97 + i),
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

ModelerCubit opened({int count = 2}) {
  final it = cpuTestDevice(width: 8, height: 8);
  final history = ModelHistory(cubes(count));
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  return ModelerCubit()..opened(
    history,
    renderer: Renderer.create(device: it.device),
    stage: stage,
  );
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

void main() {
  test('three commands within the debounce window cost one write', () {
    fakeAsync((async) {
      final cubit = opened();
      final storage = FakeBinaryStorage();
      final controller = AutosaveController(
        cubit: cubit,
        storage: storage,
        sessionId: 'test-session',
      );
      addTearDown(controller.dispose);

      final ids = ready(cubit).project.objects.map((o) => o.id).toList();
      cubit.ran(Rename(id: ids[0], to: 'one'));
      async.elapse(const Duration(seconds: 1));
      cubit.ran(Rename(id: ids[1], to: 'two'));
      async.elapse(const Duration(seconds: 1));
      cubit.ran(Rename(id: ids[0], to: 'three'));

      // Still inside the debounce window counted from the third edit.
      async.elapse(const Duration(seconds: 1));
      expect(storage.writeCount, 0);

      // Mutation: poll `shouldSave` with the *first* edit's time rather than
      // the latest. This elapse alone would then already be past the
      // debounce and this assertion would catch a write that should not
      // have happened yet.
      async.elapse(const Duration(seconds: 2));
      expect(storage.writeCount, 1);

      // Nothing edited since; well short of minInterval, so no second write.
      async.elapse(const Duration(seconds: 5));
      expect(storage.writeCount, 1);
    });
  });

  test('a clean document is never written', () {
    fakeAsync((async) {
      final cubit = opened();
      final storage = FakeBinaryStorage();
      final controller = AutosaveController(
        cubit: cubit,
        storage: storage,
        sessionId: 'test-session',
      );
      addTearDown(controller.dispose);

      async.elapse(const Duration(minutes: 1));

      expect(storage.writeCount, 0);
    });
  });

  test('write() == false is reported once, not on every poll', () {
    fakeAsync((async) {
      final cubit = opened();
      final storage = FakeBinaryStorage()..refuse = true;
      final issues = <String>[];
      final controller = AutosaveController(
        cubit: cubit,
        storage: storage,
        sessionId: 'test-session',
        onIssue: issues.add,
      );
      addTearDown(controller.dispose);

      final id = ready(cubit).project.objects.first.id;
      cubit.ran(Rename(id: id, to: 'renamed'));

      // Past the debounce once, then well past it again without any further
      // edit: the storage keeps refusing every attempt in between.
      async.elapse(const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 20));

      // Mutation: drop the `_lastAttemptFailed` gate and call `onIssue` on
      // every refused attempt. Several polls landed in that window above.
      expect(issues, hasLength(1));
    });
  });

  test('an autosave keeps repeating on minInterval while still dirty', () {
    fakeAsync((async) {
      final cubit = opened();
      final storage = FakeBinaryStorage();
      final controller = AutosaveController(
        cubit: cubit,
        storage: storage,
        sessionId: 'test-session',
      );
      addTearDown(controller.dispose);

      final id = ready(cubit).project.objects.first.id;
      cubit.ran(Rename(id: id, to: 'renamed'));

      async.elapse(const Duration(seconds: 3));
      expect(storage.writeCount, 1);

      // A document with no real save in between stays dirty, and the plan's
      // own "at most once per 15s" is a ceiling on how often, not a promise
      // it stops — an unattended session with real edits pending should not
      // go a whole crash without a fresher copy than its first one.
      async.elapse(const Duration(seconds: 15));
      expect(storage.writeCount, 2);
    });
  });

  // `ux-01`. The three tests above all pass against the build whose autosave
  // never wrote a byte for a whole session, because a fake `BinaryStorage`
  // has no directories in it. These drive the real one.
  group('ux-01: the write a real storage actually does', () {
    test('the autosave key lands on disk, directory and all', () async {
      final Directory root = await Directory.systemTemp.createTemp('autosave');
      addTearDown(() => root.deleteSync(recursive: true));
      final storage = FileBinaryStorage(
        appName: 'flutter3d_modeler',
        directory: root,
      );

      // The real key, not a flat name: `autosave/<hash>`, whose parent is a
      // directory nothing had created. Mutation: create the storage's own
      // root rather than the file's own parent, and this answers `false`.
      final String key = recoveryPathFor(null, sessionId: 'a-session');
      expect(key, contains('/'));
      final wrote = await storage.write(key, Uint8List.fromList(<int>[1, 2]));

      expect(wrote, isTrue);
      expect(File('${root.path}/$key').existsSync(), isTrue);
      expect(await storage.read(key), Uint8List.fromList(<int>[1, 2]));
    });

    test('and a storage with nowhere to write says why', () async {
      final Directory root = await Directory.systemTemp.createTemp('autosave');
      addTearDown(() => root.deleteSync(recursive: true));
      // A file where the directory should be: `createSync` refuses with a
      // real reason, the same shape a full disk or a locked folder gives,
      // and without a `chmod` that would answer differently as root.
      File('${root.path}/blocked').writeAsStringSync('not a directory');
      final issues = IssueLog();
      final storage = FileBinaryStorage(
        appName: 'flutter3d_modeler',
        directory: Directory('${root.path}/blocked'),
        onIssue: issues.add,
      );

      final wrote = await storage.write('probe', Uint8List.fromList(<int>[1]));

      expect(wrote, isFalse);
      // Mutation: swallow the exception into a bare `false`. The controller
      // then has nothing but "could not write" to put on the status line —
      // the sentence the live run found unactionable.
      expect(issues.issues, hasLength(1));
      expect(issues.issues.single, contains('could not write'));
    });
  });

  group('ux-01: what the status line is told', () {
    test('the storage\'s own reason reaches onIssue, not a bare phrase', () {
      fakeAsync((async) {
        final cubit = opened();
        final storage = FakeBinaryStorage()..refuse = true;
        final issues = IssueLog()..add(const Issue('storage: disk is full'));
        final said = <String>[];
        final controller = AutosaveController(
          cubit: cubit,
          storage: storage,
          sessionId: 'test-session',
          issues: issues,
          onIssue: said.add,
        );
        addTearDown(controller.dispose);

        final id = ready(cubit).project.objects.first.id;
        cubit.ran(Rename(id: id, to: 'renamed'));
        async.elapse(const Duration(seconds: 3));

        // Mutation: report `'could not write'` regardless of what the storage
        // said. A person then cannot tell a missing folder from a full disk.
        expect(said, <String>['disk is full']);
        expect(controller.isFailing, isTrue);
      });
    });

    test('and a write that works again is reported too', () {
      fakeAsync((async) {
        final cubit = opened();
        final storage = FakeBinaryStorage()..refuse = true;
        var recovered = 0;
        final controller = AutosaveController(
          cubit: cubit,
          storage: storage,
          sessionId: 'test-session',
          onRecovered: () => recovered++,
        );
        addTearDown(controller.dispose);

        final id = ready(cubit).project.objects.first.id;
        cubit.ran(Rename(id: id, to: 'renamed'));
        async.elapse(const Duration(seconds: 3));
        expect(controller.isFailing, isTrue);

        storage.refuse = false;
        async.elapse(const Duration(seconds: 20));

        // Mutation: never call `onRecovered`. "Autosave is not working" then
        // stays on the status line for the rest of the session, with an
        // offer to show a folder that is no longer the problem.
        expect(recovered, 1);
        expect(controller.isFailing, isFalse);
      });
    });
  });
}
