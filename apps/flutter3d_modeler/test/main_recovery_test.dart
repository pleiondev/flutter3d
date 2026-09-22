/// `findRecovery`: the pure-IO half of `ui-18`'s own "предложение
/// восстановить" — no `BuildContext`, no dialog, just storage in and a
/// decoded project (or nothing) out.
///
///     flutter test test/main_recovery_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class FakeBinaryStorage implements BinaryStorage {
  final Map<String, Uint8List> documents = <String, Uint8List>{};
  int removeCount = 0;

  @override
  Future<Uint8List?> read(String name) async => documents[name];

  @override
  Future<bool> write(String name, Uint8List contents) async {
    documents[name] = contents;
    return true;
  }

  @override
  Future<void> remove(String name) async {
    removeCount++;
    documents.remove(name);
  }
}

ModelProject cube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

void main() {
  test('nothing under the key: no recovery to offer', () async {
    final storage = FakeBinaryStorage();
    final read = await findRecovery(storage, 'a-session');
    expect(read, isNull);
  });

  test('a real autosave decodes back to its own project', () async {
    final storage = FakeBinaryStorage();
    final project = cube();
    final key = recoveryPathFor(null, sessionId: 'first-session');
    storage.documents[key] = writeProject(project);

    final read = await findRecovery(storage, 'first-session');

    expect(read, isNotNull);
    expect(read!.project.objects.single.name, 'cube');
  });

  test('a session id names its own key, not any other session\'s', () async {
    // Mutation: hard-code the key derivation to one literal session id
    // instead of reading the `sessionId` parameter — this test and the one
    // above use two different, genuinely distinct ids specifically so a
    // single hard-coded literal cannot satisfy both.
    final storage = FakeBinaryStorage();
    storage.documents[recoveryPathFor(null, sessionId: 'second-session')] =
        writeProject(cube());

    final read = await findRecovery(storage, 'first-session');

    expect(read, isNull);
  });

  test('a corrupt entry is refused and removed, not offered', () async {
    final storage = FakeBinaryStorage();
    final key = recoveryPathFor(null, sessionId: 'a-session');
    // Mutation: skip removing a corrupt entry. Every launch after this one
    // would keep reading the same garbage and finding the same nothing —
    // removeCount would stay 0 instead of counting the cleanup.
    storage.documents[key] = Uint8List.fromList(utf8.encode('not a project'));

    final read = await findRecovery(storage, 'a-session');

    expect(read, isNull);
    expect(storage.documents.containsKey(key), isFalse);
    expect(storage.removeCount, 1);
  });
}
