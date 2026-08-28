import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../animation/animation.dart';
import '../../geometry/geometry.dart';
import '../model_document.dart';
import 'f3d_format.dart';

// The header and section directory are parsed here; reading each section's
// records is split into its own file by theme (geometry, scene, materials,
// animation). Every one of them calls the private byte-view helpers declared
// below, so they are `part`s of this library rather than files that import
// it — see each part's doc comment for why. The `late final` fields that
// cache each section's result stay on the class itself, because a field
// (unlike a method) cannot be added to a class from an extension.
part 'f3d_loader_animation.dart';
part 'f3d_loader_geometry.dart';
part 'f3d_loader_materials.dart';
part 'f3d_loader_scene.dart';

/// A `.f3d` file, read as a [ModelDocument].
///
/// The point of the format, and the reason `ModelDocument` was made an
/// abstraction in the first place: `ModelAsset.fromDocument`, the resource cache
/// and the instancing path are all untouched by this file existing. Adding a
/// format meant writing a decoder, not editing the loader.
///
/// Nothing is parsed eagerly. The header and the section directory are read to
/// find where things are, and every array the engine asks for afterwards is a
/// **view over the file bytes** — `Float32List.view` on the same buffer, no copy
/// and no per-element work. That is what makes loading a converted teapot a
/// different order of magnitude from parsing the OBJ it came from.
final class F3dDocument extends ModelDocument {
  F3dDocument._(this._bytes, this._view, this._sections);

  final Uint8List _bytes;
  final ByteData _view;
  final Map<int, _Section> _sections;

  /// Reads the header of [bytes]. The body is decoded lazily.
  ///
  /// Throws [F3dFormatException] rather than returning null: a caller that
  /// picked this decoder has already decided the bytes are a `.f3d`, and a
  /// silent null would surface later as an empty model.
  factory F3dDocument.parse(Uint8List bytes) {
    if (bytes.lengthInBytes < kF3dHeaderBytes) {
      throw F3dFormatException(
        'File is ${bytes.lengthInBytes} bytes, too short for a header.',
      );
    }

    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final magic = view.getUint32(0, Endian.little);
    if (magic != kF3dMagic) {
      throw F3dFormatException(
        'Not a .f3d file: magic is 0x${magic.toRadixString(16)}, expected '
        '0x${kF3dMagic.toRadixString(16)}.',
      );
    }

    final version = view.getUint32(4, Endian.little);
    if (version != kF3dVersion) {
      throw F3dFormatException(
        'File is version $version, this build reads $kF3dVersion. Re-run '
        'tool/convert_asset.dart.',
      );
    }

    final sectionCount = view.getUint32(8, Endian.little);
    final directoryEnd = kF3dHeaderBytes + sectionCount * kF3dSectionEntryBytes;
    if (directoryEnd > bytes.lengthInBytes) {
      throw F3dFormatException(
        'Section directory claims $sectionCount entries, which runs past the '
        'end of a ${bytes.lengthInBytes}-byte file.',
      );
    }

    final sections = <int, _Section>{};
    for (var i = 0; i < sectionCount; i++) {
      final entry = kF3dHeaderBytes + i * kF3dSectionEntryBytes;
      final kind = view.getUint32(entry, Endian.little);
      final offset = view.getUint32(entry + 4, Endian.little);
      final length = view.getUint32(entry + 8, Endian.little);
      final count = view.getUint32(entry + 12, Endian.little);

      if (offset + length > bytes.lengthInBytes) {
        throw F3dFormatException(
          'Section $kind runs from $offset for $length bytes, past the end of '
          'a ${bytes.lengthInBytes}-byte file.',
        );
      }
      // Later duplicates win, and unknown kinds are kept rather than rejected:
      // a newer writer may add a section this build has no idea about, and
      // ignoring it is exactly what the directory is for.
      sections[kind] = _Section(offset, length, count);
    }

    return F3dDocument._(bytes, view, sections);
  }

  _Section _section(int kind) => _sections[kind] ?? const _Section(0, 0, 0);

  /// Absolute byte offset of a blob entry, as seen by the underlying buffer.
  ///
  /// [_bytes] may itself be a view into a larger buffer, so its own offset has
  /// to be added — reading a file straight from disk gives zero, but a `.f3d`
  /// carved out of an archive would not.
  int _blobOffset(int relative) =>
      _bytes.offsetInBytes + _section(F3dSection.blob).offset + relative;

  /// A `Float32List` over the file bytes, copying only if it has to.
  ///
  /// The writer aligns every blob entry to four bytes, so the view path is the
  /// normal one. The copy exists for the case the writer cannot control: a
  /// caller handing over bytes whose own offset is not a multiple of four, where
  /// `Float32List.view` throws rather than returning something wrong.
  Float32List _floats(int relative, int count) {
    final absolute = _blobOffset(relative);
    if (absolute % 4 != 0) {
      return Float32List.fromList(
        Float32List.sublistView(
          Uint8List.fromList(
            _bytes.buffer.asUint8List(absolute, count * 4),
          ).buffer.asUint8List(),
        ),
      );
    }
    return Float32List.view(_bytes.buffer, absolute, count);
  }

  Uint32List _uint32s(int relative, int count) {
    final absolute = _blobOffset(relative);
    if (absolute % 4 != 0) {
      final out = Uint32List(count);
      for (var i = 0; i < count; i++) {
        out[i] = _view.getUint32(
          _section(F3dSection.blob).offset + relative + i * 4,
          Endian.little,
        );
      }
      return out;
    }
    return Uint32List.view(_bytes.buffer, absolute, count);
  }

  Int32List _int32s(int relative, int count) {
    final absolute = _blobOffset(relative);
    if (absolute % 4 != 0) {
      final out = Int32List(count);
      for (var i = 0; i < count; i++) {
        out[i] = _view.getInt32(
          _section(F3dSection.blob).offset + relative + i * 4,
          Endian.little,
        );
      }
      return out;
    }
    return Int32List.view(_bytes.buffer, absolute, count);
  }

  String? _string(int offset, int length) {
    if (length == 0) return null;
    final strings = _section(F3dSection.strings);
    final start = _bytes.offsetInBytes + strings.offset + offset;
    return utf8.decode(_bytes.buffer.asUint8List(start, length));
  }

  int _recordOffset(int kind, int index, int recordBytes) =>
      _section(kind).offset + index * recordBytes;

  // Each field below caches one section's decode, done lazily and once; the
  // method it calls lives in the theme's `part` file (see the imports above).
  late final List<VertexLayout> _layouts = _readLayouts();

  final Map<int, MeshData> _meshCache = <int, MeshData>{};

  @override
  late final List<ModelSurface> surfaces = _readSurfaces();

  @override
  late final List<SurfaceMaterial> materials = _readMaterials();

  @override
  late final List<EncodedImage> images = _readImages();

  @override
  late final List<ModelNode> nodes = _readNodes();

  @override
  late final List<int> roots = _readRoots();

  @override
  late final List<AnimationClip> animations = _readAnimations();

  @override
  late final List<ModelSkin> skins = _readSkins();

  @override
  late final List<String> warnings = _readWarnings();

  // ----------------------------------------------------------------- warnings

  List<String> _readWarnings() {
    final table = _section(F3dSection.warnings);
    return <String>[
      for (var i = 0; i < table.count; i++)
        _string(
              _view.getUint32(
                table.offset + i * F3dRecord.warning,
                Endian.little,
              ),
              _view.getUint32(
                table.offset + i * F3dRecord.warning + 4,
                Endian.little,
              ),
            ) ??
            '',
    ];
  }

  @override
  String toString() =>
      'F3dDocument(${surfaces.length} surfaces, $vertexCount '
      'vertices, ${materials.length} materials, ${images.length} images, '
      '${nodes.length} nodes, ${animations.length} animations)';
}

/// Where one section lives.
final class _Section {
  const _Section(this.offset, this.length, this.count);

  final int offset;
  final int length;

  /// Elements, for the fixed-record tables; zero for raw byte sections.
  final int count;
}

/// True when [bytes] begins with the `.f3d` magic.
///
/// Cheap enough to call before committing to a decoder, which is what the format
/// sniffer in `model_loader.dart` does.
bool isF3dFile(Uint8List bytes) {
  if (bytes.lengthInBytes < 4) return false;
  return bytes[0] == 0x46 && // F
      bytes[1] == 0x33 && //    3
      bytes[2] == 0x44 && //    D
      bytes[3] == 0x0A; //      \n
}
