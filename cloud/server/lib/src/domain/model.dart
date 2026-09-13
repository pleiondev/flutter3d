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
/// Three, and each is one a person can read in a minute and a tool can name by
/// its SPDX identifier. No "all rights reserved": a model nobody may use is a
/// model that does not belong in a public catalogue, and it can stay private.
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
  );

  const Licence(this.spdx, this.label, this.url, {required this.requiresAttribution});

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
    this.licence,
    this.publishedAt,
    this.ownerHandle,
    this.ownerName,
  });

  final int id;
  final int ownerId;

  /// Unique among its owner's models; the address is `/m/<id>-<slug>`, so two
  /// people can each have a `chair`.
  final String slug;

  final String title;
  final String description;
  final Visibility visibility;
  final Licence? licence;

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
  final bounded = slug.length > 60 ? slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '') : slug;
  return bounded.isEmpty ? 'model' : bounded;
}
