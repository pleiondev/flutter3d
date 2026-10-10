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

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show FormatSpec, ResourceException;

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

  /// The layout version [encode] writes, and the newest [decode] reads.
  ///
  /// **A bundle is a build artifact, so a version it does not match is a
  /// rebuild, not a lost file** (decision 8 of `tasks/1.0-stability.md`).
  /// `flutter3d_build` puts this number, with every section's own version, in
  /// the stamp it keys its material cache on, so a flutter3d update that moves
  /// any of them rebuilds every bundle on the next build. [decode] still reads
  /// every container version up to this one, and refuses a newer bundle with
  /// [ShaderBundleException.stale] set, which tells the caller that rebuilding
  /// cures it.
  static const int formatVersion = 1;

  /// F3SB for a `FormatRegistry`.
  ///
  /// A binary format: its envelope is the `F3SB` magic and the version word
  /// after it, and each section carries a version of its own. The strings in
  /// it are stage and section names the packer chose, never a Dart
  /// identifier's `.name`.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.shaderBundle',
    version: formatVersion,
    suffixes: <String>['.f3dshaders'],
    fixture: 'test/fixtures/v<N>/effects.f3shaders',
    enveloped: false,
    magic: <int>[0x46, 0x33, 0x53, 0x42],
  );

  /// The section the Impeller backend reads: `impellerc` output, as it is.
  static const String impellerSection = 'impeller';

  /// The section the WebGL backend reads: GLSL ES 3.00 sources by name, as
  /// JSON. `flutter3d_webgl` says what the document looks like.
  static const String webglSection = 'webgl';

  /// The section the WebGPU backend reads: WGSL sources **and the reflection
  /// that goes with them**, as JSON. `flutter3d_webgpu` says what the document
  /// looks like.
  ///
  /// The two sections above carry code and nothing else, because whatever
  /// reads them can be asked afterwards what is inside: `impellerc`'s
  /// flatbuffer describes its own uniforms, and a WebGL context answers
  /// `getUniformLocation` for a program it has linked. A WGSL module answers
  /// neither. The browser compiles the text and hands back something that will
  /// not say which group and binding a sampler landed on, so the payload has
  /// to carry the answers beside the code: the name of every uniform block
  /// with the offset of each member, the group-and-binding pair for each
  /// texture and each sampler, and the location every vertex attribute was
  /// given, by name. Reflection and code travel together because a section
  /// holding one without the other is a section a device can compile and
  /// cannot bind.
  ///
  /// **The payload carries a version of its own**, inside the document, and it
  /// is not [formatVersion]. The container's version is a fact about the
  /// header and the section table, which every backend already shipped reads
  /// unchanged however this section grows; the reflection's shape is a fact
  /// between one packer and one backend, and it will move again while the
  /// container stands still. Two versions because there are two agreements,
  /// and bumping the outer one for the inner would refuse bundles to three
  /// backends that were never asked to care.
  ///
  /// [sdk] says nothing about this section, so the backend that reads it never
  /// asks [compiledFor] and the answer would be false in any case. A bundle
  /// whose only section is this one leaves the field empty, and empty matches
  /// nothing by design; a bundle that also carries an Impeller section does
  /// have a token, but that token is `impellerc`'s and this section was not
  /// built by it. This is right rather than missing: WGSL is text the browser
  /// compiles when the page loads, and nothing in the path is pinned to a
  /// Flutter release for the check to be about. Anybody moved to "fix" it
  /// would be inventing a version to compare.
  static const String webgpuSection = 'webgpu';

  /// The section a backend that compiles nothing reads — `P8`: the source of
  /// every stage written in the engine's material language, by stage name,
  /// as JSON. See [encodeMaterialSection].
  ///
  /// **The source rather than anything made from it.** The software
  /// rasteriser runs Dart and evaluates the language itself, so the text is
  /// all it needs; and a runtime that has to know how to bind a material —
  /// which maps it samples, which lighting model stands for it — reads the
  /// answer out of the same text instead of a second description that could
  /// disagree with the stage beside it.
  static const String materialSection = 'material';

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
  /// Throws [ShaderBundleException] for anything that is not a bundle: the wrong
  /// magic, a version this reader does not know, a length that runs off the
  /// end, or a string field that is not UTF-8. Refused rather than returning
  /// null because the caller is a device being handed bytes it was told were
  /// shaders, and the two ways that can be wrong — not a bundle, and a bundle
  /// it cannot run — deserve the same exception with different words.
  static ShaderBundle decode(ByteData bytes) {
    final reader = _Reader(bytes);
    if (bytes.lengthInBytes < 8 || reader.ascii(4) != magic) {
      throw const ShaderBundleException(
        name: '',
        reason: 'the bytes are not a flutter3d shader bundle (no F3SB header)',
      );
    }
    // Every container version up to this one: a later layout reads the older
    // header the older way here, before the sections are taken. Version 1 is
    // the only layout so far. Mutation: put back `!=` and bump the constant,
    // and the v1 fixture under `test/fixtures/` is refused.
    final version = reader.u32();
    if (version < 1 || version > formatVersion) {
      throw ShaderBundleException(
        name: '',
        reason:
            'the bundle is format version $version and this reader knows up '
            'to $formatVersion. It was packed by another flutter3d; rebuild '
            'it with this one (flutter3d_build does so on the next build)',
        stale: true,
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
    } on ShaderBundleException catch (refused) {
      // The reader cannot know the name when it runs off the end; the name is
      // known here, and a refusal that names the bundle is the point.
      throw ShaderBundleException(
        name: name,
        reason: refused.reason,
        stale: refused.stale,
      );
    }
  }
}

/// Raised when a device will not load a bundle, and says which and why.
///
/// One exception for every reason — bytes that are not a bundle, a section the
/// backend has none of, an SDK it was not compiled on, a stage the backend
/// cannot run, a bundle built by another flutter3d than the code reading it —
/// because the caller does one thing with all of them: report the bundle by
/// name and keep the shaders it had. A device never answers a bundle it
/// refuses with an empty library, because an empty library looks exactly like
/// a bundle whose stages nobody asked for.
///
/// **The stale case is this type too**, with [stale] set. It used to be a
/// second exception in `flutter3d` that wrapped this one to add the asset and
/// what the page was doing about it; now the engine throws this with [asset],
/// [refreshing] and [advice] filled in, and a caller catches one type.
final class ShaderBundleException extends ResourceException {
  const ShaderBundleException({
    required this.name,
    required this.reason,
    this.stale = false,
    this.asset,
    this.refreshing = false,
    this.advice,
  });

  /// The bundle's own name, or empty when the bytes never got that far.
  final String name;

  /// What the device said about it: which version it is and which this code
  /// reads, which section is missing.
  final String reason;

  /// Whether the bundle is sound but was built by another toolchain — a
  /// container or section version this build does not read, or an SDK the
  /// compiled section was not made with — so rebuilding it from its sources
  /// cures the refusal. False for bytes that are not a bundle at all, or a
  /// bundle missing what this backend needs.
  ///
  /// Bundles are build artifacts: `flutter3d_build` rebuilds a material's
  /// bundle whenever any of these versions moves, and an application that
  /// meets a stale one at run time has a bundle the build did not make.
  final bool stale;

  /// The asset key the bundle was loaded from, when the engine loaded it from
  /// one; null for bytes a caller handed the device directly.
  final String? asset;

  /// Whether the page is reloading to fetch a matching bundle and code. Only
  /// ever true for a [stale] bundle on the web, the first time this tab meets
  /// it: the server is serving files from two builds, and a reload fetches
  /// one. A caller showing the refusal can say "refreshing" instead of
  /// "rebuild".
  final bool refreshing;

  /// What a person does about it — rebuild, redeploy, wait for the reload —
  /// when the code that threw knows; null otherwise.
  final String? advice;

  @override
  String get message {
    final what = asset != null
        ? '$asset was refused'
        : name.isEmpty
        ? 'a shader bundle was refused'
        : 'the shader bundle "$name" was refused';
    return advice == null ? '$what: $reason' : '$what: $reason. $advice';
  }

  @override
  String toString() => message;
}

/// A cursor over [ShaderBundle.decode]'s input that refuses to read past the
/// end rather than throwing a `RangeError` with no bundle in the message.
final class _Reader {
  _Reader(this._bytes);

  final ByteData _bytes;
  int _at = 0;

  void _need(int count) {
    if (_at + count > _bytes.lengthInBytes) {
      throw const ShaderBundleException(
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
    final String text;
    try {
      text = utf8.decode(
        _bytes.buffer.asUint8List(_bytes.offsetInBytes + _at, length),
      );
    } on FormatException catch (error) {
      // The decoder's own exception would be the one thing `decode` lets out
      // that is not a refusal; a string that is not UTF-8 is bytes that are
      // not a bundle, and says so the same way.
      throw ShaderBundleException(
        name: '',
        reason: 'a string field in the header is not UTF-8: ${error.message}',
      );
    }
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

/// The version of [ShaderBundle.materialSection]'s payload that
/// [encodeMaterialSection] writes and the newest [decodeMaterialSection]
/// reads.
///
/// A payload from a newer packer is refused as stale rather than read: the
/// bundle is a build artifact, and the build that made it is the one to make
/// it again.
const int materialSectionVersion = 1;

/// The payload of [ShaderBundle.materialSection]: each stage's
/// material-language source, by stage name — `P8`.
///
/// Versioned inside the document, as the WebGPU section is, so the payload
/// can grow without the container's version moving.
ByteData encodeMaterialSection(Map<String, String> sources) {
  final text = jsonEncode(<String, Object?>{
    'version': materialSectionVersion,
    'stages': <String, String>{
      for (final name in sources.keys.toList()..sort()) name: sources[name]!,
    },
  });
  return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
}

/// The sources [encodeMaterialSection] wrote, or empty when [bundle] has no
/// material section. Throws a [ShaderBundleException] naming the bundle for
/// one that is not that payload, and a stale one for a payload newer than
/// [materialSectionVersion].
Map<String, String> decodeMaterialSection(ShaderBundle bundle) {
  final section = bundle.sections[ShaderBundle.materialSection];
  if (section == null) return const <String, String>{};
  ShaderBundleException notThePayload(String why) => ShaderBundleException(
    name: bundle.name,
    reason: 'its "${ShaderBundle.materialSection}" section $why',
  );
  final Object? json;
  try {
    json = jsonDecode(
      utf8.decode(
        section.buffer.asUint8List(
          section.offsetInBytes,
          section.lengthInBytes,
        ),
      ),
    );
  } on FormatException catch (error) {
    throw notThePayload('is not JSON: ${error.message}');
  }
  if (json is! Map<String, Object?> ||
      json['stages'] is! Map<String, Object?>) {
    throw notThePayload('is not its payload');
  }
  // Every payload version up to this build's; a newer one is the bundle
  // being stale, which a rebuild cures. Mutation: compare with `!=` and a
  // bumped constant refuses every bundle already built.
  final version = json['version'];
  if (version is! int || version < 1 || version > materialSectionVersion) {
    throw ShaderBundleException(
      name: bundle.name,
      reason:
          'its "${ShaderBundle.materialSection}" section is version $version '
          'and this build reads up to $materialSectionVersion; rebuild the '
          'bundle with this flutter3d',
      stale: true,
    );
  }
  return <String, String>{
    for (final MapEntry(:key, :value)
        in (json['stages']! as Map<String, Object?>).entries)
      key: value is String
          ? value
          : throw notThePayload('holds a source of "$key" that is not text'),
  };
}
