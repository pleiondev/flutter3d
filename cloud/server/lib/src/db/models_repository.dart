/// Models and the files they point at, as rows.
///
/// **Who may see a model is not decided here.** Every read takes an id and
/// returns the row; the handler that asked holds the session and applies
/// `canView`/`canEdit` from `domain/access.dart`. One rule in one place, rather
/// than a `where owner_id = …` that one query remembers and the next forgets.
library;

import 'package:postgres/postgres.dart';

import '../domain/model.dart';
import 'database.dart';

/// A file a model owns: its source, or its preview picture.
class StoredFile {
  const StoredFile({
    required this.blobSha256,
    required this.bytes,
    required this.contentType,
    required this.filename,
  });

  final String blobSha256;
  final int bytes;
  final String contentType;
  final String filename;
}

enum FileKind {
  source('source'),
  preview('preview');

  const FileKind(this.column);

  final String column;
}

class ModelsRepository {
  const ModelsRepository(this._db);

  final Database _db;

  static const _columns = '''
    m.id, m.owner_id, m.slug, m.title, m.description, m.visibility, m.licence,
    m.source_format, m.triangle_count, m.size_bytes, m.created_at, m.updated_at,
    m.published_at, u.handle as owner_handle, u.display_name as owner_name,
    exists (
      select 1 from model_files f where f.model_id = m.id and f.kind = 'preview'
    ) as has_preview
  ''';

  /// Stores a model and its source file in one transaction.
  ///
  /// The blob is already on disk by the time this runs — a row that points at a
  /// file is only ever written after the file exists, never the other way round.
  Future<ModelRecord> create({
    required int ownerId,
    required String title,
    required String sourceFormat,
    required int triangleCount,
    required StoredFile source,
  }) => _db.transaction((session) async {
    final inserted = await session.execute(
      Sql.named('''
        insert into models (owner_id, slug, title, source_format, triangle_count, size_bytes)
        values (@owner, @slug, @title, @format, @triangles, @size)
        returning id
      '''),
      parameters: {
        'owner': ownerId,
        'slug': slugify(title),
        'title': title,
        'format': sourceFormat,
        'triangles': triangleCount,
        'size': source.bytes,
      },
    );
    final id = inserted.first[0]! as int;
    await _putFile(session, id, FileKind.source, source);
    return (await _byId(session, id))!;
  });

  Future<ModelRecord?> byId(int id) => _db.run((session) => _byId(session, id));

  /// Every model [ownerId] keeps, most recently changed first.
  Future<List<ModelRecord>> ofOwner(int ownerId) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select $_columns from models m join users u on u.id = m.owner_id
        where m.owner_id = @owner
        order by m.updated_at desc
      '''),
      parameters: {'owner': ownerId},
    );
    return [for (final row in rows) _record(row)];
  });

  /// Published models, newest first, [limit] at a time.
  ///
  /// Paged by the publication time of the last one seen rather than by an
  /// offset, so a model published while somebody reads page two does not push
  /// a model they have already seen onto page three.
  Future<List<ModelRecord>> published({int limit = 24, DateTime? before}) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            select $_columns from models m join users u on u.id = m.owner_id
            where m.visibility = 'public'
              and (@before::timestamptz is null or m.published_at < @before::timestamptz)
            order by m.published_at desc
            limit @limit
          '''),
          parameters: {'before': before, 'limit': limit},
        );
        return [for (final row in rows) _record(row)];
      });

  Future<StoredFile?> fileOf(int modelId, FileKind kind) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select blob_sha256, bytes, content_type, filename from model_files
        where model_id = @id and kind = @kind
      '''),
      parameters: {'id': modelId, 'kind': kind.column},
    );
    if (rows.isEmpty) return null;
    final map = rows.first.toColumnMap();
    return StoredFile(
      blobSha256: map['blob_sha256'] as String,
      bytes: map['bytes'] as int,
      contentType: map['content_type'] as String,
      filename: map['filename'] as String,
    );
  });

  /// Sets the preview picture, replacing any earlier one.
  ///
  /// Returns the hash of the picture it replaced, so the caller can ask whether
  /// anything still points at it.
  Future<String?> setPreview(int modelId, StoredFile preview) =>
      _db.transaction((session) async {
        final previous = await session.execute(
          Sql.named('''
            select blob_sha256 from model_files where model_id = @id and kind = 'preview'
          '''),
          parameters: {'id': modelId},
        );
        await _putFile(session, modelId, FileKind.preview, preview);
        return previous.isEmpty ? null : previous.first[0]! as String;
      });

  Future<void> describe(int modelId, {required String title, required String description}) =>
      _db.run((session) async {
        await session.execute(
          Sql.named('''
            update models
            set title = @title, slug = @slug, description = @description, updated_at = now()
            where id = @id
          '''),
          parameters: {
            'id': modelId,
            'title': title,
            'slug': slugify(title),
            'description': description,
          },
        );
      });

  /// Makes a model public under [licence].
  ///
  /// `published_at` is kept from the first publication: taking a model down and
  /// putting it back should not move it to the top of the catalogue.
  Future<void> publish(int modelId, Licence licence) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update models
        set visibility = 'public', licence = @licence,
            published_at = coalesce(published_at, now()), updated_at = now()
        where id = @id
      '''),
      parameters: {'id': modelId, 'licence': licence.spdx},
    );
  });

  /// Makes a model private again. The licence stays recorded: whoever
  /// downloaded it while it was public received it under those terms.
  Future<void> unpublish(int modelId) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update models set visibility = 'private', updated_at = now() where id = @id
      '''),
      parameters: {'id': modelId},
    );
  });

  /// Deletes a model and returns the hashes of the files it pointed at.
  Future<List<String>> delete(int modelId) => _db.transaction((session) async {
    final files = await session.execute(
      Sql.named('select blob_sha256 from model_files where model_id = @id'),
      parameters: {'id': modelId},
    );
    await session.execute(
      Sql.named('delete from models where id = @id'),
      parameters: {'id': modelId},
    );
    return [for (final row in files) row[0]! as String];
  });

  /// The hashes of every file [ownerId]'s models point at — collected before an
  /// account is deleted, because the cascade takes the rows with it.
  Future<List<String>> blobsOfOwner(int ownerId) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select f.blob_sha256 from model_files f join models m on m.id = f.model_id
        where m.owner_id = @owner
      '''),
      parameters: {'owner': ownerId},
    );
    return [for (final row in rows) row[0]! as String];
  });

  /// Whether any model still points at [sha256].
  ///
  /// Asked before a blob is deleted: two people who uploaded the same file
  /// share one blob, and deleting one of their models must not take the other's.
  Future<bool> isReferenced(String sha256) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select 1 from model_files where blob_sha256 = @sha limit 1'),
      parameters: {'sha': sha256},
    );
    return rows.isNotEmpty;
  });

  Future<void> _putFile(Session session, int modelId, FileKind kind, StoredFile file) =>
      session.execute(
        Sql.named('''
          insert into model_files (model_id, kind, blob_sha256, bytes, content_type, filename)
          values (@id, @kind, @sha, @bytes, @type, @name)
          on conflict (model_id, kind) do update
          set blob_sha256 = excluded.blob_sha256, bytes = excluded.bytes,
              content_type = excluded.content_type, filename = excluded.filename,
              created_at = now()
        '''),
        parameters: {
          'id': modelId,
          'kind': kind.column,
          'sha': file.blobSha256,
          'bytes': file.bytes,
          'type': file.contentType,
          'name': file.filename,
        },
      );

  Future<ModelRecord?> _byId(Session session, int id) async {
    final rows = await session.execute(
      Sql.named('''
        select $_columns from models m join users u on u.id = m.owner_id
        where m.id = @id
      '''),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _record(rows.first);
  }

  static ModelRecord _record(ResultRow row) {
    final map = row.toColumnMap();
    return ModelRecord(
      id: map['id'] as int,
      ownerId: map['owner_id'] as int,
      slug: map['slug'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      visibility: Visibility.of(map['visibility'] as String),
      licence: Licence.of(map['licence'] as String?),
      sourceFormat: map['source_format'] as String,
      triangleCount: map['triangle_count'] as int,
      sizeBytes: map['size_bytes'] as int,
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
      publishedAt: map['published_at'] as DateTime?,
      hasPreview: map['has_preview'] as bool,
      ownerHandle: map['owner_handle'] as String?,
      ownerName: map['owner_name'] as String?,
    );
  }
}
