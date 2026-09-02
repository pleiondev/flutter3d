/// A shader bundle that arrives as bytes rather than as an asset.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
///
/// ## Why a container, and not the compiler's own output
///
/// Every backend compiles the same GLSL into something only it can read:
/// `impellerc` writes a flatbuffer for Impeller, the WebGL backend takes GLSL
/// ES text and hands it to the browser, and the software rasteriser takes
/// nothing at all because its stages are Dart. A file an application can
/// download once and hand to *whichever* device it is running on therefore has
/// to hold more than one of those, and has to say which is which. That is the
/// whole of what this format is: a header, the names of the stages inside, and
/// one section per backend.
///
/// The header carries the SDK the compiled section was built with, because a
/// compiled shader bundle is tied to the Flutter version and the failure when
/// the two disagree is not an error — it is a stage that parses and draws
/// something else. A backend that reads a compiled section refuses a bundle
/// whose SDK is not the one it is running on, and refuses it **by name**, so
/// the message says which file to rebuild rather than which draw went wrong.
///
/// The stage list is in the header rather than derived from the sections, for
/// the backend that has no section: the software rasteriser answers a loaded
/// bundle with the Dart stages it already has, and the list is how it knows
/// which names the bundle claims — and which of them it cannot honour.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One entry point a bundle claims to hold.
final class ShaderBundleStage {
  const ShaderBundleStage(this.name, {required this.fragment});

  /// The name the engine asks a [ShaderLibrary] for.
  final String name;

  /// Whether this is a fragment stage; a vertex stage otherwise.
  final bool fragment;

  @override
  String toString() => '$name (${fragment ? 'fragment' : 'vertex'})';
}

/// A loadable shader bundle: a name, the SDK it was compiled on, the stages it
/// claims, and a compiled section per backend that needs one.
///
/// A value. [encode] writes the bytes a device's `loadShaders` takes and
/// [decode] reads them back; the two are checked against each other by
/// `test/shader_bundle_test.dart`, which is what makes the format a fact
/// rather than a description.
final class ShaderBundle {
  const ShaderBundle({
    required this.name,
    required this.sdk,
    required this.stages,
    this.sections = const <String, ByteData>{},
  });

  /// The four bytes every bundle starts with.
  static const String magic = 'F3SB';

  /// The layout version [encode] writes and [decode] accepts.
  static const int formatVersion = 1;

  /// The section the Impeller backend reads: `impellerc` output, as it is.
  static const String impellerSection = 'impeller';

  /// The section the WebGL backend reads: GLSL ES 3.00 sources by name, as
  /// JSON. `flutter3d_webgl` says what the document looks like.
  static const String webglSection = 'webgl';

  /// What the bundle is called, and what a refusal names.
  final String name;

  /// The Dart SDK the compiled section was built with: the first token of
  /// `dart --version`, which is also the first token of `Platform.version` in
  /// the running application. `3.13.0`, say. One release of Flutter ships one
  /// Dart, so the token identifies the `impellerc` that wrote the section.
  ///
  /// Empty for a bundle with nothing compiled in it.
  final String sdk;

  /// The entry points this bundle claims, whichever section answers them.
  final List<ShaderBundleStage> stages;

  /// Backend-specific payloads by section id.
  final Map<String, ByteData> sections;

  /// Every name in [stages].
  Iterable<String> get names => stages.map((ShaderBundleStage s) => s.name);

  /// The payload for [id], or null when the bundle carries none for it.
  ByteData? section(String id) => sections[id];

  /// Whether [running] is the SDK this bundle was compiled with.
  ///
  /// Only the first token of either side is compared, so a `Platform.version`
  /// with its channel and date attached matches the bare version the packer
  /// wrote. An empty [sdk] matches nothing: a bundle that does not say what
  /// compiled it cannot be trusted by a backend that runs compiled code.
  bool compiledFor(String running) =>
      sdk.isNotEmpty && _token(sdk) == _token(running);

  static String _token(String version) => version.trim().split(' ').first;

  /// The bytes, in the layout [decode] reads.
  ///
  /// Little-endian throughout. Strings are a `uint32` byte length and UTF-8;
  /// a stage is a string and one byte, 1 for fragment; a section is a string
  /// id, a `uint32` length and the bytes.
  ByteData encode() {
    final out = BytesBuilder(copy: false);
    void u8(int value) => out.addByte(value);
    void u32(int value) {
      out.add(
        Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
      );
    }

    void string(String value) {
      final bytes = utf8.encode(value);
      u32(bytes.length);
      out.add(bytes);
    }

    out.add(ascii.encode(magic));
    u32(formatVersion);
    string(name);
    string(sdk);
    u32(stages.length);
    for (final stage in stages) {
      string(stage.name);
      u8(stage.fragment ? 1 : 0);
    }
    u32(sections.length);
    for (final entry in sections.entries) {
      string(entry.key);
      final bytes = entry.value;
      u32(bytes.lengthInBytes);
      out.add(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }
    return out.takeBytes().buffer.asByteData();
  }

  /// Reads what [encode] wrote.
  ///
  /// Throws [ShaderBundleRefused] for anything that is not a bundle: the wrong
  /// magic, a version this reader does not know, or a length that runs off the
  /// end. Refused rather than returning null because the caller is a device
  /// being handed bytes it was told were shaders, and the two ways that can be
  /// wrong — not a bundle, and a bundle it cannot run — deserve the same
  /// exception with different words.
  static ShaderBundle decode(ByteData bytes) {
    final reader = _Reader(bytes);
    if (bytes.lengthInBytes < 8 || reader.ascii(4) != magic) {
      throw const ShaderBundleRefused(
        name: '',
        reason: 'the bytes are not a flutter3d shader bundle (no F3SB header)',
      );
    }
    final version = reader.u32();
    if (version != formatVersion) {
      throw ShaderBundleRefused(
        name: '',
        reason:
            'the bundle is format version $version and this reader knows '
            'only $formatVersion',
      );
    }
    final name = reader.string();
    try {
      final sdk = reader.string();
      final stageCount = reader.u32();
      final stages = <ShaderBundleStage>[
        for (var i = 0; i < stageCount; i++)
          ShaderBundleStage(reader.string(), fragment: reader.u8() == 1),
      ];
      final sectionCount = reader.u32();
      final sections = <String, ByteData>{
        for (var i = 0; i < sectionCount; i++)
          reader.string(): reader.bytes(reader.u32()),
      };
      return ShaderBundle(
        name: name,
        sdk: sdk,
        stages: stages,
        sections: sections,
      );
    } on ShaderBundleRefused catch (refused) {
      // The reader cannot know the name when it runs off the end; the name is
      // known here, and a refusal that names the bundle is the point.
      throw ShaderBundleRefused(name: name, reason: refused.reason);
    }
  }
}

/// Raised when a device will not load a bundle, and says which and why.
///
/// One exception for every reason — bytes that are not a bundle, a section the
/// backend has none of, an SDK it was not compiled on, a stage the backend
/// cannot run — because the caller does one thing with all of them: report the
/// bundle by name and keep the shaders it had. A device never answers a bundle
/// it refuses with an empty library, because an empty library looks exactly
/// like a bundle whose stages nobody asked for.
final class ShaderBundleRefused implements Exception {
  const ShaderBundleRefused({required this.name, required this.reason});

  /// The bundle's own name, or empty when the bytes never got that far.
  final String name;

  final String reason;

  @override
  String toString() => name.isEmpty
      ? 'a shader bundle was refused: $reason'
      : 'the shader bundle "$name" was refused: $reason';
}

/// A cursor over [ShaderBundle.decode]'s input that refuses to read past the
/// end rather than throwing a `RangeError` with no bundle in the message.
final class _Reader {
  _Reader(this._bytes);

  final ByteData _bytes;
  int _at = 0;

  void _need(int count) {
    if (_at + count > _bytes.lengthInBytes) {
      throw const ShaderBundleRefused(
        name: '',
        reason: 'the bundle ends before its header says it does',
      );
    }
  }

  int u8() {
    _need(1);
    return _bytes.getUint8(_at++);
  }

  int u32() {
    _need(4);
    final value = _bytes.getUint32(_at, Endian.little);
    _at += 4;
    return value;
  }

  String ascii(int length) {
    _need(length);
    final text = String.fromCharCodes(
      _bytes.buffer.asUint8List(_bytes.offsetInBytes + _at, length),
    );
    _at += length;
    return text;
  }

  String string() {
    final length = u32();
    _need(length);
    final text = utf8.decode(
      _bytes.buffer.asUint8List(_bytes.offsetInBytes + _at, length),
    );
    _at += length;
    return text;
  }

  /// A copy, not a view: a backend hands a section to a native parser, and a
  /// view with an offset is the sort of thing one of them reads from zero.
  ByteData bytes(int length) {
    _need(length);
    final copy = Uint8List.fromList(
      _bytes.buffer.asUint8List(_bytes.offsetInBytes + _at, length),
    );
    _at += length;
    return copy.buffer.asByteData();
  }
}
