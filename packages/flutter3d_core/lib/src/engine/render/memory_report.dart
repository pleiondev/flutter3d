/// What the renderer holds on the device, by category — `A5.24`.
///
/// **An account, not a measurement.** No backend says how much memory a
/// texture or a buffer actually takes: a driver pads rows, aligns levels,
/// keeps tiles and compresses behind the API's back. What this counts is
/// what the data itself needs — `TextureHandle.estimatedBytes`,
/// `GeometryBuffer.lengthInBytes` — which is the floor every backend sits on
/// and the number a budget is set against. Where even that is unknown, as
/// for a compiled pipeline, the entry counts objects and leaves the bytes
/// null rather than inventing them.
library;

/// What an entry of a [MemoryReport] is.
///
/// **A final class with const instances rather than an enum**, so a
/// category added later — a compute buffer, a texture array — breaks no
/// switch anybody has written over these.
final class MemoryCategory {
  const MemoryCategory._(this.name);

  /// The name a report's JSON uses.
  final String name;

  /// Images the materials, the environment and the engine's own stand-ins
  /// sample: what a level loaded.
  static const MemoryCategory textures = MemoryCategory._('textures');

  /// Buffers that are not a mesh's own vertices and indices on the device:
  /// the CPU copies of meshes kept for picking and physics.
  static const MemoryCategory buffers = MemoryCategory._('buffers');

  /// What the renderer draws into: the frame's targets, the shadow atlases,
  /// histories, probe and reflection captures, and the pool of transient
  /// targets, lent and free.
  static const MemoryCategory renderTargets = MemoryCategory._('renderTargets');

  /// The vertices and indices of every mesh the scene draws.
  static const MemoryCategory meshes = MemoryCategory._('meshes');

  /// Shader stages and the pipelines linked from them. Counted, not
  /// weighed: no backend says what a pipeline costs.
  static const MemoryCategory shaders = MemoryCategory._('shaders');

  /// All of them, in the order a report lists them.
  static const List<MemoryCategory> values = <MemoryCategory>[
    textures,
    buffers,
    renderTargets,
    meshes,
    shaders,
  ];

  @override
  String toString() => 'MemoryCategory.$name';
}

/// One line of a [MemoryReport].
final class MemoryEntry {
  const MemoryEntry({
    required this.category,
    required this.label,
    required this.count,
    this.bytes,
  });

  final MemoryCategory category;

  /// What it is, in words a reader recognises: `hdrColor`, `shadow atlas`,
  /// a material's name.
  final String label;

  /// How many objects the line stands for.
  final int count;

  /// What they hold, or null when nothing can say — see the library
  /// comment.
  final int? bytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'label': label,
    'count': count,
    'bytes': bytes,
  };

  @override
  String toString() =>
      'MemoryEntry(${category.name}, $label, $count, ${bytes ?? '?'} B)';
}

/// What the renderer holds on the device, line by line and by category —
/// `Renderer.memoryReport`.
///
/// **Each object once.** A texture a material samples and the renderer also
/// keeps is counted under the first category that claims it, in the order
/// [MemoryCategory] lists them, and a mesh two nodes share is one line.
final class MemoryReport {
  MemoryReport(List<MemoryEntry> entries)
    : entries = List<MemoryEntry>.unmodifiable(entries);

  final List<MemoryEntry> entries;

  /// What [category] holds, in bytes, counting only the lines that know.
  int bytesOf(MemoryCategory category) => entries
      .where((MemoryEntry e) => e.category == category)
      .fold(0, (int sum, MemoryEntry e) => sum + (e.bytes ?? 0));

  /// How many objects [category] holds.
  int countOf(MemoryCategory category) => entries
      .where((MemoryEntry e) => e.category == category)
      .fold(0, (int sum, MemoryEntry e) => sum + e.count);

  /// Every category's bytes together.
  int get totalBytes =>
      entries.fold(0, (int sum, MemoryEntry e) => sum + (e.bytes ?? 0));

  /// The categories with their totals, then every line, largest first
  /// within each.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalBytes': totalBytes,
    'categories': <String, Object?>{
      for (final category in MemoryCategory.values)
        category.name: <String, Object?>{
          'bytes': bytesOf(category),
          'count': countOf(category),
        },
    },
    'entries': <Map<String, Object?>>[
      for (final category in MemoryCategory.values)
        ...(entries.where((MemoryEntry e) => e.category == category).toList()
              ..sort(
                (MemoryEntry a, MemoryEntry b) =>
                    (b.bytes ?? -1).compareTo(a.bytes ?? -1),
              ))
            .map((MemoryEntry e) => e.toJson()),
    ],
  };

  @override
  String toString() =>
      'MemoryReport(${entries.length} entries, $totalBytes bytes)';
}
