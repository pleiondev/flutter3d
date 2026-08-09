import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../animation/animation.dart';
import '../../geometry/geometry.dart';
import '../model_document.dart';
import 'f3d_format.dart';

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
    final directoryEnd =
        kF3dHeaderBytes + sectionCount * kF3dSectionEntryBytes;
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

  _Section _section(int kind) =>
      _sections[kind] ?? const _Section(0, 0, 0);

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

  // ------------------------------------------------------------------ layouts

  late final List<VertexLayout> _layouts = _readLayouts();

  List<VertexLayout> _readLayouts() {
    final table = _section(F3dSection.layouts);
    return <VertexLayout>[
      for (var i = 0; i < table.count; i++) _readLayout(i),
    ];
  }

  VertexLayout _readLayout(int index) {
    final o = _recordOffset(F3dSection.layouts, index, F3dRecord.layout);
    final attributeCount = _view.getUint32(o, Endian.little);
    final first = _view.getUint32(o + 4, Endian.little);

    return VertexLayout(<VertexAttribute>[
      for (var a = 0; a < attributeCount; a++)
        () {
          final ao = _recordOffset(
            F3dSection.attributes,
            first + a,
            F3dRecord.attribute,
          );
          final name = _string(
                _view.getUint32(ao, Endian.little),
                _view.getUint32(ao + 4, Endian.little),
              ) ??
              '';
          return VertexAttribute(
            name,
            _view.getUint32(ao + 8, Endian.little),
          );
        }(),
    ]);
  }

  // ------------------------------------------------------------------- meshes

  /// Meshes are cached by index so a mesh shared between surfaces stays one
  /// object, exactly as the decoders produce it — the GPU upload path
  /// deduplicates on identity, and rebuilding a `MeshData` per surface would
  /// quietly defeat it.
  final Map<int, MeshData> _meshCache = <int, MeshData>{};

  MeshData _mesh(int index) => _meshCache.putIfAbsent(index, () {
        final o = _recordOffset(F3dSection.meshes, index, F3dRecord.mesh);
        final layoutIndex = _view.getUint32(o, Endian.little);
        final vertexOffset = _view.getUint32(o + 4, Endian.little);
        final vertexBytes = _view.getUint32(o + 8, Endian.little);
        final indexOffset = _view.getUint32(o + 12, Endian.little);
        final indexBytes = _view.getUint32(o + 16, Endian.little);

        if (layoutIndex >= _layouts.length) {
          throw F3dFormatException(
            'meshes[$index] names layout $layoutIndex, but the file has '
            '${_layouts.length}.',
          );
        }

        return MeshData(
          layout: _layouts[layoutIndex],
          vertices: _floats(vertexOffset, vertexBytes ~/ 4),
          indices: _uint32s(indexOffset, indexBytes ~/ 4),
        );
      });

  // ----------------------------------------------------------------- surfaces

  @override
  late final List<ModelSurface> surfaces = _readSurfaces();

  List<ModelSurface> _readSurfaces() {
    final table = _section(F3dSection.surfaces);
    return <ModelSurface>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(
            F3dSection.surfaces,
            i,
            F3dRecord.surface,
          );
          final materialIndex = _view.getInt32(o + 4, Endian.little);

          final storage = Float32List(16);
          for (var e = 0; e < 16; e++) {
            storage[e] = _view.getFloat32(o + 20 + e * 4, Endian.little);
          }

          return ModelSurface(
            mesh: _mesh(_view.getUint32(o, Endian.little)),
            materialIndex: materialIndex < 0 ? null : materialIndex,
            name: _string(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ),
            flipWinding: _view.getUint32(o + 16, Endian.little) & 1 != 0,
            skinIndex: () {
              final packed = _view.getUint32(o + 16, Endian.little) >> 1;
              return packed == 0 ? null : packed - 1;
            }(),
            transform: Matrix4.fromFloat32List(storage),
          );
        }(),
    ];
  }

  // ---------------------------------------------------------------- materials

  @override
  late final List<SurfaceMaterial> materials = _readMaterials();

  List<SurfaceMaterial> _readMaterials() {
    final table = _section(F3dSection.materials);
    return <SurfaceMaterial>[
      for (var i = 0; i < table.count; i++) _readMaterial(i),
    ];
  }

  SurfaceMaterial _readMaterial(int index) {
    var o = _recordOffset(F3dSection.materials, index, F3dRecord.material);

    final name = _string(
      _view.getUint32(o, Endian.little),
      _view.getUint32(o + 4, Endian.little),
    );
    o += 8;

    final baseColor = Vector4(
      _view.getFloat32(o, Endian.little),
      _view.getFloat32(o + 4, Endian.little),
      _view.getFloat32(o + 8, Endian.little),
      _view.getFloat32(o + 12, Endian.little),
    );
    o += 16;

    final metallic = _view.getFloat32(o, Endian.little);
    final roughness = _view.getFloat32(o + 4, Endian.little);
    final normalScale = _view.getFloat32(o + 8, Endian.little);
    final occlusionStrength = _view.getFloat32(o + 12, Endian.little);
    o += 16;

    final emissive = Vector3(
      _view.getFloat32(o, Endian.little),
      _view.getFloat32(o + 4, Endian.little),
      _view.getFloat32(o + 8, Endian.little),
    );
    final emissiveStrength = _view.getFloat32(o + 12, Endian.little);
    o += 16;

    final alphaModeIndex = _view.getUint32(o, Endian.little);
    final alphaCutoff = _view.getFloat32(o + 4, Endian.little);
    final doubleSided = _view.getUint32(o + 8, Endian.little) != 0;
    final unlit = _view.getUint32(o + 12, Endian.little) != 0;
    o += 16;

    final bindings = <TextureBinding?>[];
    for (var b = 0; b < 5; b++) {
      bindings.add(_readBinding(o));
      o += F3dRecord.textureBinding;
    }

    return SurfaceMaterial(
      name: name,
      baseColor: baseColor,
      metallic: metallic,
      roughness: roughness,
      baseColorTexture: bindings[0],
      metallicRoughnessTexture: bindings[1],
      normalTexture: bindings[2],
      normalScale: normalScale,
      occlusionTexture: bindings[3],
      occlusionStrength: occlusionStrength,
      emissiveTexture: bindings[4],
      emissive: emissive,
      emissiveStrength: emissiveStrength,
      alphaMode: alphaModeIndex < SurfaceAlphaMode.values.length
          ? SurfaceAlphaMode.values[alphaModeIndex]
          : SurfaceAlphaMode.opaque,
      alphaCutoff: alphaCutoff,
      doubleSided: doubleSided,
      unlit: unlit,
    );
  }

  TextureBinding? _readBinding(int offset) {
    final imageIndex = _view.getInt32(offset, Endian.little);
    if (imageIndex < 0) return null;

    final flags = _view.getUint32(offset + 8, Endian.little);
    TextureWrap wrap(int shift) {
      final value = (flags >> shift) & F3dSamplingFlags.wrapMask;
      return value < TextureWrap.values.length
          ? TextureWrap.values[value]
          : TextureWrap.repeat;
    }

    return TextureBinding(
      imageIndex: imageIndex,
      texCoordSet: _view.getUint32(offset + 4, Endian.little),
      sampling: TextureSampling(
        magLinear: flags & F3dSamplingFlags.magLinear != 0,
        minLinear: flags & F3dSamplingFlags.minLinear != 0,
        useMipmaps: flags & F3dSamplingFlags.useMipmaps != 0,
        wrapS: wrap(F3dSamplingFlags.wrapSShift),
        wrapT: wrap(F3dSamplingFlags.wrapTShift),
      ),
    );
  }

  // ------------------------------------------------------------------- images

  @override
  late final List<EncodedImage> images = _readImages();

  List<EncodedImage> _readImages() {
    final table = _section(F3dSection.images);
    return <EncodedImage>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.images, i, F3dRecord.image);
          final dataOffset = _view.getUint32(o, Endian.little);
          final dataLength = _view.getUint32(o + 4, Endian.little);

          return EncodedImage(
            // A view, not a copy: image bytes are the largest thing in the file
            // and the decoder downstream only reads them.
            bytes: _bytes.buffer.asUint8List(
              _blobOffset(dataOffset),
              dataLength,
            ),
            name: _string(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ),
            mimeType: _string(
              _view.getUint32(o + 16, Endian.little),
              _view.getUint32(o + 20, Endian.little),
            ),
          );
        }(),
    ];
  }

  // -------------------------------------------------------------------- nodes

  @override
  late final List<ModelNode> nodes = _readNodes();

  List<ModelNode> _readNodes() {
    final table = _section(F3dSection.nodes);
    return <ModelNode>[
      for (var i = 0; i < table.count; i++)
        () {
          var o = _recordOffset(F3dSection.nodes, i, F3dRecord.node);

          final name = _string(
            _view.getUint32(o, Endian.little),
            _view.getUint32(o + 4, Endian.little),
          );
          o += 8;

          final translation = Vector3(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
          );
          o += 12;

          final rotation = Quaternion(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
            _view.getFloat32(o + 12, Endian.little),
          );
          o += 16;

          final scale = Vector3(
            _view.getFloat32(o, Endian.little),
            _view.getFloat32(o + 4, Endian.little),
            _view.getFloat32(o + 8, Endian.little),
          );
          o += 12;

          return ModelNode(
            name: name,
            translation: translation,
            rotation: rotation,
            scale: scale,
            children: _int32s(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ).toList(),
            surfaces: _int32s(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ).toList(),
          );
        }(),
    ];
  }

  @override
  late final List<int> roots = _readRoots();

  List<int> _readRoots() {
    final table = _section(F3dSection.roots);
    return <int>[
      for (var i = 0; i < table.count; i++)
        _view.getInt32(table.offset + i * 4, Endian.little),
    ];
  }

  // --------------------------------------------------------------- animations

  @override
  late final List<AnimationClip> animations = _readAnimations();

  List<AnimationClip> _readAnimations() {
    final table = _section(F3dSection.animations);
    return <AnimationClip>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(
            F3dSection.animations,
            i,
            F3dRecord.animation,
          );
          final firstTrack = _view.getUint32(o + 8, Endian.little);
          final trackCount = _view.getUint32(o + 12, Endian.little);

          return AnimationClip(
            name: _string(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ),
            tracks: <AnimationTrack>[
              for (var t = 0; t < trackCount; t++) _readTrack(firstTrack + t),
            ],
          );
        }(),
    ];
  }

  AnimationTrack _readTrack(int index) {
    final o = _recordOffset(F3dSection.tracks, index, F3dRecord.track);
    final pathIndex = _view.getUint32(o + 4, Endian.little);
    final interpolationIndex = _view.getUint32(o + 8, Endian.little);

    if (pathIndex >= AnimationPath.values.length ||
        interpolationIndex >= AnimationInterpolation.values.length) {
      throw F3dFormatException(
        'tracks[$index] names path $pathIndex and interpolation '
        '$interpolationIndex, which this build does not have.',
      );
    }

    return AnimationTrack(
      nodeIndex: _view.getUint32(o, Endian.little),
      path: AnimationPath.values[pathIndex],
      interpolation: AnimationInterpolation.values[interpolationIndex],
      componentCount: _view.getUint32(o + 12, Endian.little),
      times: _floats(
        _view.getUint32(o + 16, Endian.little),
        _view.getUint32(o + 20, Endian.little),
      ),
      values: _floats(
        _view.getUint32(o + 24, Endian.little),
        _view.getUint32(o + 28, Endian.little),
      ),
    );
  }

  // -------------------------------------------------------------------- skins

  @override
  late final List<ModelSkin> skins = _readSkins();

  List<ModelSkin> _readSkins() {
    final table = _section(F3dSection.skins);
    return <ModelSkin>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.skins, i, F3dRecord.skin);
          final jointCount = _view.getUint32(o + 12, Endian.little);
          final matrices = _floats(
            _view.getUint32(o + 16, Endian.little),
            jointCount * 16,
          );
          final root = _view.getInt32(o + 20, Endian.little);

          return ModelSkin(
            name: _string(
              _view.getUint32(o, Endian.little),
              _view.getUint32(o + 4, Endian.little),
            ),
            joints: _int32s(
              _view.getUint32(o + 8, Endian.little),
              jointCount,
            ).toList(),
            inverseBindMatrices: <Matrix4>[
              for (var j = 0; j < jointCount; j++)
                Matrix4.fromFloat32List(
                  Float32List.sublistView(matrices, j * 16, j * 16 + 16),
                ),
            ],
            skeletonRoot: root < 0 ? null : root,
          );
        }(),
    ];
  }

  // ----------------------------------------------------------------- warnings

  @override
  late final List<String> warnings = _readWarnings();

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
  String toString() => 'F3dDocument(${surfaces.length} surfaces, $vertexCount '
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
