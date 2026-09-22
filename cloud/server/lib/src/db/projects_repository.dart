/// Projects, as rows.
///
/// **Who may see/edit is not decided here.** Every read takes an id and
/// returns the row; the handler that asked holds the session and applies
/// `canEditProject` from `domain/access.dart`. One rule in one place, rather
/// than a `where owner_id = …` that one query remembers and the next forgets.
library;

import 'package:postgres/postgres.dart';

import '../domain/model.dart' show slugify;
import '../domain/project.dart';
import 'database.dart';

class ProjectsRepository {
  const ProjectsRepository(this._db);

  final Database _db;

  static const _columns =
      'id, owner_id, slug, title, description, created_at, updated_at';

  Future<ProjectRecord> create({required int ownerId, required String title}) =>
      _db.run((session) async {
        final inserted = await session.execute(
          Sql.named('''
        insert into projects (owner_id, slug, title)
        values (@owner, @slug, @title)
        returning $_columns
      '''),
          parameters: {
            'owner': ownerId,
            'slug': slugify(title),
            'title': title,
          },
        );
        return _record(inserted.first);
      });

  Future<ProjectRecord?> byId(int id) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('select $_columns from projects where id = @id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _record(rows.first);
  });

  /// Every project [ownerId] keeps, most recently changed first.
  Future<List<ProjectRecord>> ofOwner(int ownerId) => _db.run((session) async {
    final rows = await session.execute(
      Sql.named('''
        select $_columns from projects
        where owner_id = @owner
        order by updated_at desc
      '''),
      parameters: {'owner': ownerId},
    );
    return [for (final row in rows) _record(row)];
  });

  Future<void> describe(
    int projectId, {
    required String title,
    required String description,
  }) => _db.run((session) async {
    await session.execute(
      Sql.named('''
        update projects
        set title = @title, slug = @slug, description = @description, updated_at = now()
        where id = @id
      '''),
      parameters: {
        'id': projectId,
        'title': title,
        'slug': slugify(title),
        'description': description,
      },
    );
  });

  /// Deletes a project. Its own models are not deleted, and nothing here
  /// walks them to detach them — `models.project_id`'s own `on delete set
  /// null` already makes them personal at the database layer, the moment
  /// this row goes.
  Future<void> delete(int projectId) => _db.run((session) async {
    await session.execute(
      Sql.named('delete from projects where id = @id'),
      parameters: {'id': projectId},
    );
  });

  static ProjectRecord _record(ResultRow row) {
    final map = row.toColumnMap();
    return ProjectRecord(
      id: map['id'] as int,
      ownerId: map['owner_id'] as int,
      slug: map['slug'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
    );
  }
}
