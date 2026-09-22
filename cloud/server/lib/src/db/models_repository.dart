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

/// One past save of a model's source file, as `revisionsOf` lists it — the
/// file's own metadata plus who saved it and when, not the bytes themselves.
class RevisionRecord {
  const RevisionRecord({
    required this.id,
    required this.modelId,
    required this.blobSha256,
    required this.bytes,
    required this.contentType,
    required this.filename,
    required this.triangleCount,
    required this.createdAt,
    required this.createdBy,
  });

  final int id;
  final int modelId;
  final String blobSha256;
  final int bytes;
  final String contentType;
  final String filename;
  final int triangleCount;
  final DateTime createdAt;
  final int createdBy;
}

class ModelsRepository {
  const ModelsRepository(this._db);

  final Database _db;

  static const _columns = '''
    m.id, m.owner_id, m.project_id, m.slug, m.title, m.description, m.visibility,
    m.licence, m.category, m.source_format, m.triangle_count, m.size_bytes,
    m.created_at, m.updated_at, m.published_at,
    u.handle as owner_handle, u.display_name as owner_name,
    exists (
      select 1 from model_files f where f.model_id = m.id and f.kind = 'preview'
    ) as has_preview
  ''';

  /// Stores a model and its source file in one transaction.
  ///
  /// The blob is already on disk by the time this runs — a row that points at a
  /// file is only ever written after the file exists, never the other way round.
  /// [projectId] is optional: a model can be created standing alone, the same
  /// as it can be created inside a project — [moveToProject] can change this
  /// either way afterward.
  Future<ModelRecord> create({
    required int ownerId,
    required String title,
    required String sourceFormat,
    required int triangleCount,
    required StoredFile source,
    int? projectId,
  }) => _db.transaction((session) async {
    final inserted = await session.execute(
      Sql.named('''
        insert into models (owner_id, project_id, slug, title, source_format, triangle_count, size_bytes)
        values (@owner, @project, @slug, @title, @format, @triangles, @size)
        returning id
      '''),
      parameters: {
        'owner': ownerId,
        'project': projectId,
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

  /// Moves [modelId] into [projectId], out to no project (`null`), or between
  /// projects — at any time after creation, the same "edit any time" spirit
  /// [describe] already has.
  ///
  /// **Who may ask is still not decided here** — the handler checks `canEdit`
  /// on the model and `canEditProject` on the target project before this is
  /// ever called. What this does check, in the same statement as the move
  /// itself so nothing can race it, is that the model and [projectId] share
  /// an owner: a model moving into a project it does not belong with would be
  /// a corrupt row no access check downstream could put right. Returns false,
  /// moving nothing, when that is not so — or when [modelId] does not exist.
  Future<bool> moveToProject(int modelId, int? projectId) =>
      _db.run((session) async {
        final updated = await session.execute(
          Sql.named('''
            update models set project_id = @project::bigint, updated_at = now()
            where id = @id
              and (
                @project::bigint is null
                or exists (
                  select 1 from projects p
                  where p.id = @project::bigint and p.owner_id = models.owner_id
                )
              )
          '''),
          parameters: {'id': modelId, 'project': projectId},
        );
        return updated.affectedRows > 0;
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

  /// Every model currently sitting in [projectId], most recently changed
  /// first — a project's own page. **Who may ask is still not decided
  /// here**, the same as [ofOwner]: the handler checks `canEditProject` on
  /// the project before this is ever called.
  Future<List<ModelRecord>> ofProject(int projectId) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
        select $_columns from models m join users u on u.id = m.owner_id
        where m.project_id = @project
        order by m.updated_at desc
      '''),
          parameters: {'project': projectId},
        );
        return [for (final row in rows) _record(row)];
      });

  /// Published models, newest first, [limit] at a time — the showcase's own
  /// list.
  ///
  /// Paged by the publication time of the last one seen rather than by an
  /// offset, so a model published while somebody reads page two does not push
  /// a model they have already seen onto page three. Narrowed to [category]
  /// when given, and to [search] when given: [search] goes through
  /// `websearch_to_tsquery`, the safe parser built for exactly this — a text
  /// box's worth of user input, never `to_tsquery` on the raw string — matched
  /// against the `search` column the migration generates from title and
  /// description. With a [search] term, results are ranked by `ts_rank`
  /// first, published-date second; the `ts_rank` term is `0` for every row
  /// when [search] is null, so that case collapses to exactly the plain
  /// published-date ordering this method always had.
  Future<List<ModelRecord>> published({
    int limit = 24,
    DateTime? before,
    Category? category,
    String? search,
  }) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select $_columns from models m join users u on u.id = m.owner_id
        where m.visibility = 'public'
          and (@before::timestamptz is null or m.published_at < @before::timestamptz)
          and (@category::text is null or m.category = @category::text)
          and (
            @search::text is null
            or m.search @@ websearch_to_tsquery('english', @search::text)
          )
        order by
          (case
            when @search::text is null then 0
            else ts_rank(m.search, websearch_to_tsquery('english', @search::text))
          end) desc,
          m.published_at desc
        limit @limit
      '''),
      parameters: {
        'before': before,
        'limit': limit,
        'category': category?.column,
        'search': search,
      },
    );
    return [for (final row in rows) _record(row)];
  });

  Future<StoredFile?> fileOf(int modelId, FileKind kind) =>
      _db.run((session) async {
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

  /// Saves a new source file over [modelId]'s current one, keeping the file
  /// it replaces as a revision.
  ///
  /// One transaction: the new revision is recorded, `model_files` moves on to
  /// [newSource] (the existing [_putFile] helper), and the model's own
  /// denormalized columns move with it — [sizeBytes], [triangleCount] and
  /// [sourceFormat] all describe the current source, the same as [create]
  /// leaves them. The blob itself must already be on disk by the time this
  /// runs, same as [create] — a row that points at a file is only ever
  /// written after the file exists.
  Future<ModelRecord> replaceSource({
    required int modelId,
    required StoredFile newSource,
    required int triangleCount,
    required String sourceFormat,
    required int actorUserId,
  }) => _db.transaction((session) async {
    await session.execute(
      Sql.named('''
        insert into model_revisions
          (model_id, blob_sha256, bytes, content_type, filename, triangle_count, created_by)
        values (@id, @sha, @bytes, @type, @name, @triangles, @actor)
      '''),
      parameters: {
        'id': modelId,
        'sha': newSource.blobSha256,
        'bytes': newSource.bytes,
        'type': newSource.contentType,
        'name': newSource.filename,
        'triangles': triangleCount,
        'actor': actorUserId,
      },
    );
    await _putFile(session, modelId, FileKind.source, newSource);
    await session.execute(
      Sql.named('''
        update models
        set size_bytes = @bytes, triangle_count = @triangles,
            source_format = @format, updated_at = now()
        where id = @id
      '''),
      parameters: {
        'id': modelId,
        'bytes': newSource.bytes,
        'triangles': triangleCount,
        'format': sourceFormat,
      },
    );
    return (await _byId(session, modelId))!;
  });

  /// Every revision [modelId] has ever had, newest first.
  Future<List<RevisionRecord>> revisionsOf(int modelId) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            select id, model_id, blob_sha256, bytes, content_type, filename,
                   triangle_count, created_at, created_by
            from model_revisions
            where model_id = @id
            order by created_at desc
          '''),
          parameters: {'id': modelId},
        );
        return [for (final row in rows) _revision(row)];
      });

  /// One revision's file, for download — or null when [revisionId] is not a
  /// revision of [modelId].
  ///
  /// Checked together rather than [revisionId] alone, so a revision id that
  /// belongs to somebody else's model can never serve its file just because
  /// the id happens to exist.
  Future<StoredFile?> revisionFile(int modelId, int revisionId) =>
      _db.run((session) async {
        final rows = await session.execute(
          Sql.named('''
            select blob_sha256, bytes, content_type, filename
            from model_revisions
            where id = @revisionId and model_id = @modelId
          '''),
          parameters: {'revisionId': revisionId, 'modelId': modelId},
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

  Future<void> describe(
    int modelId, {
    required String title,
    required String description,
  }) => _db.run((session) async {
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

  /// Makes a model public under [licence] and [category].
  ///
  /// `published_at` is kept from the first publication: taking a model down and
  /// putting it back should not move it to the top of the catalogue.
  /// [category] is required here and nowhere earlier, the same as [licence]
  /// already is — a private model does not need one, publishing is what asks
  /// for it. Both are typed enums, so an unknown value cannot reach this
  /// query at all; the app layer is where that is refused, not a database
  /// constraint turning into a 500 — the `check` on `models.category` is only
  /// a backstop behind this.
  Future<void> publish(
    int modelId,
    Licence licence, {
    required Category category,
  }) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update models
        set visibility = 'public', licence = @licence, category = @category,
            published_at = coalesce(published_at, now()), updated_at = now()
        where id = @id
      '''),
      parameters: {
        'id': modelId,
        'licence': licence.spdx,
        'category': category.column,
      },
    );
  });

  /// Makes a model private again. The licence and category stay recorded,
  /// the same as `published_at` already does: whoever downloaded the model
  /// while it was public received it under that licence, and putting it
  /// back up later should not ask the owner to choose again or move it to
  /// the top of the catalogue.
  Future<void> unpublish(int modelId) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update models set visibility = 'private', updated_at = now() where id = @id
      '''),
      parameters: {'id': modelId},
    );
  });

  /// Deletes a model and returns the hashes of every file it pointed at —
  /// its current files and every past revision — so the caller can free
  /// whichever of those blobs nothing else still references.
  Future<List<String>> delete(int modelId) => _db.transaction((session) async {
    final files = await session.execute(
      Sql.named('select blob_sha256 from model_files where model_id = @id'),
      parameters: {'id': modelId},
    );
    final revisions = await session.execute(
      Sql.named('select blob_sha256 from model_revisions where model_id = @id'),
      parameters: {'id': modelId},
    );
    await session.execute(
      Sql.named('delete from models where id = @id'),
      parameters: {'id': modelId},
    );
    return [
      for (final row in files) row[0]! as String,
      for (final row in revisions) row[0]! as String,
    ];
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

  /// Whether any model still points at [sha256] — as a current file or as a
  /// past revision.
  ///
  /// Asked before a blob is deleted: two people who uploaded the same file
  /// share one blob, and deleting one of their models must not take the
  /// other's. Checking `model_revisions` too is what keeps a revision's own
  /// blob alive once a newer save has moved `model_files` on to a different
  /// hash — without it, saving over a model would garbage-collect its own
  /// history out from under it.
  Future<bool> isReferenced(String sha256) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select 1 from model_files where blob_sha256 = @sha
        union all
        select 1 from model_revisions where blob_sha256 = @sha
        limit 1
      '''),
      parameters: {'sha': sha256},
    );
    return rows.isNotEmpty;
  });

  Future<void> _putFile(
    Session session,
    int modelId,
    FileKind kind,
    StoredFile file,
  ) => session.execute(
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
      projectId: map['project_id'] as int?,
      slug: map['slug'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      visibility: Visibility.of(map['visibility'] as String),
      licence: Licence.of(map['licence'] as String?),
      category: Category.of(map['category'] as String?),
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

  static RevisionRecord _revision(ResultRow row) {
    final map = row.toColumnMap();
    return RevisionRecord(
      id: map['id'] as int,
      modelId: map['model_id'] as int,
      blobSha256: map['blob_sha256'] as String,
      bytes: map['bytes'] as int,
      contentType: map['content_type'] as String,
      filename: map['filename'] as String,
      triangleCount: map['triangle_count'] as int,
      createdAt: map['created_at'] as DateTime,
      createdBy: map['created_by'] as int,
    );
  }
}
