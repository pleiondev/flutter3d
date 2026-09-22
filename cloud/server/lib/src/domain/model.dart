/// A model somebody keeps here.
library;

/// Who can see a model.
enum Visibility {
  /// Its owner, and nobody else. Where every upload starts.
  private('private'),

  /// Anybody, in the catalogue and at its own address.
  public('public');

  const Visibility(this.column);

  final String column;

  static Visibility of(String column) =>
      values.firstWhere((v) => v.column == column);
}

/// The terms a published model goes out under.
///
/// Each is one a person can read in a minute and a tool can name by its SPDX
/// identifier. No "all rights reserved": a model nobody may use is a model
/// that does not belong in a public catalogue, and it can stay private.
enum Licence {
  cc0(
    'CC0-1.0',
    'CC0 — no rights reserved',
    'https://creativecommons.org/publicdomain/zero/1.0/',
    requiresAttribution: false,
  ),
  ccBy(
    'CC-BY-4.0',
    'CC BY — credit the author',
    'https://creativecommons.org/licenses/by/4.0/',
    requiresAttribution: true,
  ),
  ccBySa(
    'CC-BY-SA-4.0',
    'CC BY-SA — credit the author, share alike',
    'https://creativecommons.org/licenses/by-sa/4.0/',
    requiresAttribution: true,
  ),
  // The MIT licence's own text conditions permission on "the above copyright
  // notice and this permission notice" travelling with every copy — a
  // narrower ask than crediting the author in a byline, but still a copy
  // that arrives without it is not in compliance, so this reads as
  // attribution the same way CC BY does.
  mit(
    'MIT',
    'MIT — permissive, credit the author',
    'https://opensource.org/license/mit/',
    requiresAttribution: true,
  );

  const Licence(
    this.spdx,
    this.label,
    this.url, {
    required this.requiresAttribution,
  });

  /// What is stored, and what goes into an exported file's metadata.
  final String spdx;

  final String label;
  final String url;

  /// Whether a download must name the author. CC0 does not ask it; the
  /// catalogue shows the author anyway, because knowing who made a thing is
  /// useful whether or not the licence insists.
  final bool requiresAttribution;

  static Licence? of(String? spdx) =>
      spdx == null ? null : values.where((l) => l.spdx == spdx).firstOrNull;
}

/// What a published model is, for the showcase's own filter and search.
///
/// A short fixed list, the same taste [Licence] already shows: each one is a
/// column value the check constraint on `models.category` names by hand, and
/// this enum is the source of truth for that list — the SQL is written to
/// match it, not the other way round.
enum Category {
  characters('characters', 'Characters'),
  props('props', 'Props'),
  environments('environments', 'Environments'),
  vehicles('vehicles', 'Vehicles'),
  architecture('architecture', 'Architecture'),
  abstract('abstract', 'Abstract'),
  other('other', 'Other');

  const Category(this.column, this.label);

  /// What is stored, and what a filter is chosen by.
  final String column;

  final String label;

  static Category? of(String? column) => column == null
      ? null
      : values.where((c) => c.column == column).firstOrNull;
}

/// A model, as a list and a page see it.
class ModelRecord {
  const ModelRecord({
    required this.id,
    required this.ownerId,
    required this.slug,
    required this.title,
    required this.description,
    required this.visibility,
    required this.sourceFormat,
    required this.triangleCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    required this.hasPreview,
    this.projectId,
    this.licence,
    this.category,
    this.publishedAt,
    this.ownerHandle,
    this.ownerName,
  });

  final int id;
  final int ownerId;

  /// The project this model currently lives in, or null while it stands
  /// alone. A model may move in, out or between projects at any time — this
  /// is never fixed at creation the way [ownerId] is.
  final int? projectId;

  /// Unique among its owner's models; the address is `/m/<id>-<slug>`, so two
  /// people can each have a `chair`.
  final String slug;

  final String title;
  final String description;
  final Visibility visibility;
  final Licence? licence;

  /// Chosen at publication, the same time as [licence] — null until then,
  /// because a private model does not need one.
  final Category? category;

  /// `glb`, `gltf`, `obj` or `f3d` — what the file is, as the decoder that
  /// accepted it named it.
  final String sourceFormat;

  /// Counted from the parsed file, never taken from the client.
  final int triangleCount;

  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final bool hasPreview;

  /// Filled when the record was read together with its owner, which the
  /// catalogue does and the cabinet does not need to.
  final String? ownerHandle;
  final String? ownerName;

  /// The path this model is reached at.
  String get path => '/m/$id-$slug';

  bool get isPublic => visibility == Visibility.public;
}

/// A readable size: `812 B`, `4.2 KB`, `18.6 MB`.
String formatBytes(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

/// A slug from a title: `Old Oak Chair (v2)` becomes `old-oak-chair-v2`.
String slugify(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final bounded = slug.length > 60
      ? slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '')
      : slug;
  return bounded.isEmpty ? 'model' : bounded;
}
