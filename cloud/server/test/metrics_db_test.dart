/// [MetricsRepository] against a real database — the one place the dedup
/// arithmetic actually has rows to get wrong.
@Tags(['db'])
library;

import 'dart:io';

import 'package:flutter3d_models/src/db/database.dart';
import 'package:flutter3d_models/src/db/metrics_repository.dart';
import 'package:flutter3d_models/src/db/models_repository.dart';
import 'package:flutter3d_models/src/db/users_repository.dart';
import 'package:test/test.dart';

void main() {
  late Database db;
  late UsersRepository users;
  late ModelsRepository models;
  late MetricsRepository metrics;

  setUpAll(() async {
    final url =
        Platform.environment['MODELS_TEST_DATABASE_URL'] ??
        'postgres://models:models@localhost:55432/models';
    db = await Database.open(url);
    users = UsersRepository(db);
    models = ModelsRepository(db);
    metrics = MetricsRepository(db);
  });

  tearDownAll(() => db.close());

  setUp(
    () => db.run(
      (s) => s.execute('truncate users, rate_events restart identity cascade'),
    ),
  );

  test('an empty service reports four zeroes', () async {
    final snapshot = await metrics.snapshot();
    expect(snapshot.registeredUsers, 0);
    expect(snapshot.verifiedUsers, 0);
    expect(snapshot.models, 0);
    expect(snapshot.storageBytes, 0);
  });

  test('counts every account, and separately the confirmed ones', () async {
    final ann = (await users.create(
      email: 'ann@example.com',
      handle: 'ann',
      displayName: 'Ann',
      passwordHash: 'x',
    ))!;
    await users.create(
      email: 'bo@example.com',
      handle: 'bo',
      displayName: 'Bo',
      passwordHash: 'x',
    );
    await users.markEmailVerified(ann.id);

    final snapshot = await metrics.snapshot();
    expect(snapshot.registeredUsers, 2);
    expect(snapshot.verifiedUsers, 1);
  });

  test('storage counts a shared blob once, not once per model', () async {
    final ann = (await users.create(
      email: 'ann@example.com',
      handle: 'ann',
      displayName: 'Ann',
      passwordHash: 'x',
    ))!;

    // Two uploads of the same cube: same hash, same size, two model rows.
    final sharedCube = StoredFile(
      blobSha256: 'a' * 64,
      bytes: 1000,
      contentType: 'model/gltf-binary',
      filename: 'cube.glb',
    );
    await models.create(
      ownerId: ann.id,
      title: 'Cube one',
      sourceFormat: 'glb',
      triangleCount: 12,
      source: sharedCube,
    );
    await models.create(
      ownerId: ann.id,
      title: 'Cube two',
      sourceFormat: 'glb',
      triangleCount: 12,
      source: sharedCube,
    );
    // A different file, so a second hash genuinely adds to the total.
    await models.create(
      ownerId: ann.id,
      title: 'Sphere',
      sourceFormat: 'glb',
      triangleCount: 240,
      source: StoredFile(
        blobSha256: 'b' * 64,
        bytes: 500,
        contentType: 'model/gltf-binary',
        filename: 'sphere.glb',
      ),
    );

    final snapshot = await metrics.snapshot();
    expect(snapshot.models, 3);
    expect(snapshot.storageBytes, 1500); // 1000 once, plus 500 — not 2500
  });
}
