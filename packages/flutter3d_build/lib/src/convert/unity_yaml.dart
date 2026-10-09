/// Unity's text serialisation: a file of YAML documents, each headed
/// `--- !u!<class> &<fileID>`, and the `.meta` file beside every asset that
/// gives it the GUID other files name it by.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';
import '../build_exceptions.dart';

/// Unity's class numbers for the objects a converter reads.
abstract final class UnityClass {
  static const int gameObject = 1;
  static const int transform = 4;
  static const int camera = 20;
  static const int material = 21;
  static const int meshRenderer = 23;
  static const int meshFilter = 33;
  static const int light = 108;
  static const int monoBehaviour = 114;
  static const int skinnedMeshRenderer = 137;
  static const int rectTransform = 224;
  static const int prefabInstance = 1001;
}

/// One object of a Unity file.
final class UnityObject {
  const UnityObject(
    this.classId,
    this.fileId,
    this.type,
    this.fields, {
    this.stripped = false,
  });

  final int classId;
  final int fileId;

  /// The document's single top-level key: `GameObject`, `Transform`.
  final String type;

  /// What is under it, as plain maps, lists and scalars.
  final Map<String, Object?> fields;

  /// A stand-in for an object of a prefab this file instances.
  final bool stripped;

  Object? operator [](String key) => fields[key];
}

/// A reference, `{fileID: 400000, guid: abc…, type: 3}`.
typedef UnityRef = ({int fileId, String? guid});

/// [value] read as a reference, or null.
UnityRef? unityRef(Object? value) {
  if (value is! Map) return null;
  final id = value['fileID'];
  if (id is! int) return null;
  final guid = value['guid'];
  return (fileId: id, guid: guid is String ? guid : null);
}

/// A Unity text file's objects, by file ID.
///
/// Throws [SourceFormatException] for a file Unity saved as binary, which this
/// cannot read: Edit > Project Settings > Editor > Asset Serialization,
/// Force Text, makes every asset text.
Map<int, UnityObject> parseUnityYaml(String text) {
  if (!text.startsWith('%YAML') && !text.startsWith('--- !u!')) {
    throw const SourceFormatException(
      'not a Unity text asset; set Asset Serialization to Force Text in the '
      'project\'s Editor settings and save it again',
    );
  }
  final objects = <int, UnityObject>{};
  final header = RegExp(
    r'^--- !u!(\d+) &(-?\d+)( stripped)?\s*$',
    multiLine: true,
  );
  final matches = header.allMatches(text).toList();
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    // A GUID of digits and one `e` reads as a number in YAML —
    // `0000000000000000e000000000000000` is nought — so every GUID is
    // quoted before the body is parsed.
    final body = text
        .substring(match.end, end)
        .replaceAllMapped(
          RegExp(r'guid: ([0-9a-fA-F]{32})'),
          (Match m) => 'guid: "${m.group(1)}"',
        );
    final Object? parsed;
    try {
      parsed = loadYaml(body);
    } on YamlException catch (error) {
      throw SourceFormatException(
        'object &${match.group(2)}: ${error.message}',
      );
    }
    if (parsed is! Map || parsed.isEmpty) continue;
    final type = '${parsed.keys.first}';
    final fields = _plain(parsed.values.first);
    objects[int.parse(match.group(2)!)] = UnityObject(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      type,
      fields is Map<String, Object?> ? fields : <String, Object?>{},
      stripped: match.group(3) != null,
    );
  }
  return objects;
}

/// [value] with `YamlMap` and `YamlList` replaced by plain collections.
Object? _plain(Object? value) => switch (value) {
  final YamlMap map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value),
  },
  final YamlList list => <Object?>[for (final v in list) _plain(v)],
  _ => value,
};

/// The GUIDs of a Unity project's assets, from their `.meta` files.
final class UnityAssetIndex {
  UnityAssetIndex._(this.root, this._byGuid);

  /// An index of the project [file] is in: the directory above the nearest
  /// `Assets` folder, or [file]'s own directory when there is none.
  factory UnityAssetIndex.around(String file) {
    final directory = File(file).absolute.parent;
    Directory? project;
    for (var at = directory; at.parent.path != at.path; at = at.parent) {
      if (at.uri.pathSegments.where((String s) => s.isNotEmpty).lastOrNull ==
          'Assets') {
        project = at.parent;
        break;
      }
      if (Directory('${at.path}/Assets').existsSync() &&
          Directory('${at.path}/ProjectSettings').existsSync()) {
        project = at;
        break;
      }
    }
    final root = project ?? directory;
    final scan = project == null ? root : Directory('${root.path}/Assets');
    final byGuid = <String, String>{};
    if (scan.existsSync()) {
      for (final entity in scan.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.meta')) continue;
        final guid = _guidOf(entity);
        if (guid != null) {
          byGuid[guid] = entity.path.substring(0, entity.path.length - 5);
        }
      }
    }
    return UnityAssetIndex._(root.path, byGuid);
  }

  /// The project's directory.
  final String root;
  final Map<String, String> _byGuid;

  /// The asset [guid] names, or null.
  String? path(String? guid) => guid == null ? null : _byGuid[guid];

  int get length => _byGuid.length;

  static String? _guidOf(File meta) {
    for (final line in meta.readAsLinesSync().take(8)) {
      if (line.startsWith('guid: ')) return line.substring(6).trim();
    }
    return null;
  }

  /// What a model's `.meta` says: its import scale, and the names of the
  /// meshes inside it by the file ID a `MeshFilter` names them with.
  ({double scale, Map<int, String> meshes}) modelImport(String asset) {
    final meta = File('$asset.meta');
    if (!meta.existsSync()) return (scale: 1.0, meshes: const <int, String>{});
    final Object? parsed;
    try {
      parsed = loadYaml(meta.readAsStringSync());
    } on Object {
      return (scale: 1.0, meshes: const <int, String>{});
    }
    final importer = parsed is Map ? parsed['ModelImporter'] : null;
    if (importer is! Map) return (scale: 1.0, meshes: const <int, String>{});
    final meshes = importer['meshes'];
    final scale = meshes is Map && meshes['globalScale'] is num
        ? (meshes['globalScale'] as num).toDouble()
        : 1.0;
    final names = <int, String>{};
    // Unity 2019.3 on: `internalIDToNameTable`, a list of {first: {43: id},
    // second: name}. Before it: `fileIDToRecycleName`, {id: name}.
    final table = importer['internalIDToNameTable'];
    if (table is List) {
      for (final entry in table) {
        if (entry is! Map) continue;
        final first = entry['first'];
        final second = entry['second'];
        if (first is Map && second is String) {
          final id = first[43];
          if (id is int) names[id] = second;
        }
      }
    }
    final recycle = importer['fileIDToRecycleName'];
    if (recycle is Map) {
      for (final MapEntry(:key, :value) in recycle.entries) {
        if (key is int && value is String && key ~/ 100000 == 43) {
          names[key] = value;
        }
      }
    }
    return (scale: scale, meshes: names);
  }
}
