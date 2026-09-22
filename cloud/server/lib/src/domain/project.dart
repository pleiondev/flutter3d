/// A project somebody keeps here — a folder for their own models.
library;

/// A project, as a list and a page see it.
///
/// A project decides nothing about who may see or change the models inside
/// it: every model keeps its own `owner_id` and its own `visibility`, project
/// or no project, the same as a model already does on its own.
class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.ownerId,
    required this.slug,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int ownerId;

  /// Unique among its owner's projects; the address is `/p/<id>-<slug>`, the
  /// same shape a model's own path already has.
  final String slug;

  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The path this project is reached at.
  String get path => '/p/$id-$slug';
}
