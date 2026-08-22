/// The `.f3d` container: constants shared by the writer and the reader.
///
/// ## Why a format at all
///
/// The measurement in `doc/FFI-analysis.md` is the whole argument. A GLB of the
/// teapot's complexity loads in 14.8 us; the same geometry as OBJ takes 5.39 ms,
/// a factor of about 360. That gap is not the language — it is the work. OBJ is
/// text, so every number is parsed, every face is split, every vertex triple is
/// hashed and deduplicated. GLB already holds the buffers the GPU wants, and
/// loading it is mostly pointing at them.
///
/// `.f3d` takes that to its conclusion: an offline converter does the decoding
/// once, and the runtime does almost nothing. Vertex and index arrays are stored
/// exactly as `MeshData` holds them, so the loader hands out typed-data **views
/// over the file bytes** rather than copies. Nothing is decoded per load.
///
/// ## Layout
///
/// Everything is little-endian, stated rather than inherited: the host happens
/// to be little-endian today, and a format that silently depends on that breaks
/// the first time an asset is built on one machine and read on another.
///
/// ```
/// Header, 16 bytes
///   u32 magic          'F3D\n'
///   u32 version
///   u32 sectionCount
///   u32 reserved
///
/// Section directory, sectionCount x 16 bytes
///   u32 kind           see [F3dSection]
///   u32 offset         from the start of the file
///   u32 length         in bytes
///   u32 count          in elements, for the fixed-record tables
/// ```
///
/// A directory rather than a fixed set of header fields, because it makes the
/// format extensible in the only way that matters: a reader skips a kind it does
/// not know, so a later version can add a section without breaking an older
/// loader. [kVersion] then only has to change when an existing record's meaning
/// changes.
///
/// Tables hold fixed-size records so an index is an offset multiplication rather
/// than a walk. Everything variable-length — strings, vertex and index arrays,
/// image bytes, keyframe data — lives in the blob and is referenced by
/// `(offset, length)`.
///
/// ## Alignment
///
/// Every blob entry starts at a 4-byte boundary. That is not tidiness: a
/// `Float32List.view` throws unless its byte offset is a multiple of four, and
/// the whole point of the format is to build those views without copying.
library;

/// `F3D\n`, chosen so a file opened in a text editor announces itself on line
/// one and the trailing newline stops the magic from running into what follows.
const int kF3dMagic = 0x0A443346;

/// Bumped when an existing record changes meaning. Adding a section does not
/// need it — an old reader skips what it does not recognise.
const int kF3dVersion = 1;

const int kF3dHeaderBytes = 16;
const int kF3dSectionEntryBytes = 16;

/// Section kinds.
///
/// Explicit values, never the enum index: the value is written into a file that
/// outlives the source, and reordering the enum would silently reinterpret every
/// asset already on disk.
abstract final class F3dSection {
  static const int layouts = 1;
  static const int attributes = 2;
  static const int meshes = 3;
  static const int surfaces = 4;
  static const int materials = 5;
  static const int images = 6;
  static const int nodes = 7;
  static const int roots = 8;
  static const int animations = 9;
  static const int tracks = 10;
  static const int warnings = 11;
  static const int strings = 12;
  static const int blob = 13;
  static const int skins = 14;
}

/// Fixed record sizes, in bytes. All multiples of four.
abstract final class F3dRecord {
  /// u32 attributeCount, u32 firstAttribute
  static const int layout = 8;

  /// u32 nameOffset, u32 nameLength, u32 componentCount
  static const int attribute = 12;

  /// u32 layoutIndex, u32 vertexOffset, u32 vertexBytes, u32 indexOffset,
  /// u32 indexBytes, u32 vertexCount
  static const int mesh = 24;

  /// u32 meshIndex, i32 materialIndex, u32 nameOffset, u32 nameLength,
  /// u32 flags, f32`16` transform
  ///
  /// `flags` is bit 0 for flipWinding and the rest for the skin index plus one,
  /// so zero means "no skin".
  static const int surface = 84;

  /// See the writer; 132 bytes of scalars plus five texture bindings.
  static const int material = 132;

  /// u32 dataOffset, u32 dataLength, u32 nameOffset, u32 nameLength,
  /// u32 mimeOffset, u32 mimeLength
  static const int image = 24;

  /// u32 nameOffset, u32 nameLength, f32`3` translation, f32`4` rotation,
  /// f32`3` scale, u32 childOffset, u32 childCount, u32 surfaceOffset,
  /// u32 surfaceCount
  static const int node = 64;

  /// u32 nameOffset, u32 nameLength, u32 firstTrack, u32 trackCount
  static const int animation = 16;

  /// u32 nodeIndex, u32 path, u32 interpolation, u32 componentCount,
  /// u32 timesOffset, u32 timesCount, u32 valuesOffset, u32 valuesCount
  static const int track = 32;

  /// u32 offset, u32 length into the strings section
  static const int warning = 8;

  /// u32 nameOffset, u32 nameLength, u32 jointOffset, u32 jointCount,
  /// u32 matrixOffset, i32 skeletonRoot
  static const int skin = 24;

  /// One texture binding inside a material: i32 imageIndex, u32 texCoordSet,
  /// u32 samplingFlags
  static const int textureBinding = 12;
}

/// Bit positions inside a texture binding's `samplingFlags`.
///
/// Packed rather than one field each because the whole of [TextureSampling] fits
/// in eight bits, and a material carries five of these.
abstract final class F3dSamplingFlags {
  static const int magLinear = 1 << 0;
  static const int minLinear = 1 << 1;
  static const int useMipmaps = 1 << 2;

  /// Two bits each, holding a [TextureWrap] index.
  static const int wrapSShift = 3;
  static const int wrapTShift = 5;
  static const int wrapMask = 0x3;
}

/// Raised when a file is not a `.f3d`, is truncated, or claims a version this
/// build does not understand.
///
/// A distinct type rather than [FormatException] so a caller can tell "this is
/// not our format" from "this is our format and it is broken", and rebuild the
/// asset in the second case.
final class F3dFormatException implements Exception {
  const F3dFormatException(this.message);

  final String message;

  @override
  String toString() => 'F3dFormatException: $message';
}
