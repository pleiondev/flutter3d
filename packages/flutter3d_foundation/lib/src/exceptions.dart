/// The one root every exception flutter3d throws hangs from, and its four
/// families.
///
/// **Exceptions are for what a caller can meet in a correct program**: a file
/// that is not what it says, a device without a feature, a plugin that will
/// not install, a tool or a service that is not there. A caller who wants to
/// report every one of them catches [Flutter3dException]; a caller who acts on
/// one kind catches its family. A programmer's mistake (a wrong argument, a
/// call out of order) stays an [Error] and is not caught.
///
/// **The families are `abstract base class`, not `sealed`**, so a package can
/// add its own leaf to one: `flutter3d_sim` has its own format exceptions,
/// `flutter3d_education/lti.dart` its own resource ones. `base` keeps the hierarchy honest —
/// nothing can `implements` a family and claim to be one without being one —
/// and a type somebody else defines still lands in exactly one family.
///
/// **[message] is a getter**, not a field, because the leaves already had
/// their own: some keep the sentence they were given, some build it from what
/// they carry (a step's name, the device that refused). Every one of them
/// ends up with a sentence a person can read, and [cause] carries what was
/// underneath when there was something.
library;

import 'formats.dart' show DocumentFormatException;

/// The root of every exception flutter3d throws.
///
/// Catch this to report anything the engine refused without listing its
/// packages' types. Extend a family rather than this: [Flutter3dFormatException],
/// [CapabilityException], [PluginException] or [ResourceException].
abstract base class Flutter3dException implements Exception {
  const Flutter3dException();

  /// What went wrong, as a sentence that names the thing it went wrong with.
  String get message;

  /// What was thrown underneath, when this one wraps it; null otherwise.
  Object? get cause => null;

  @override
  String toString() => cause == null ? message : '$message (caused by $cause)';
}

/// Bytes or text that are not what they claim to be, or are a version this
/// build cannot read: a level, a model, an image, a trace, a shader source.
///
/// **Named with the prefix on purpose.** `dart:core` already has a
/// `FormatException`, and readers used to throw it bare. A name of our own
/// that differs from it only by a namespace would be hidden by every
/// `import 'dart:core'` or would hide it, and `on FormatException` would read
/// the same either way. With the prefix, `on Flutter3dFormatException` always
/// means ours and `on FormatException` always means the SDK's.
abstract base class Flutter3dFormatException extends Flutter3dException {
  const Flutter3dFormatException();
}

/// Something asked of a device, a backend or a platform that it does not do:
/// a feature a backend leaves out of its features, a limit a request
/// exceeds, a check a backend declines.
///
/// A capability can be asked about before the call (`GraphicsDevice.features`
/// and its limits); this is what the call says when nobody asked.
abstract base class CapabilityException extends Flutter3dException {
  const CapabilityException();
}

/// A plugin cannot be discovered, installed, enabled or disabled, or a
/// run-time plugin did something it was not allowed to.
///
/// **A concrete class and not only a family**, unlike the other three,
/// because it was one before it had a root: the plugin manager throws it with
/// a sentence naming the plugins involved, and plugins written against the
/// first plugin API throw it too. The run-time plugins' refusals extend it.
base class PluginException extends Flutter3dException {
  const PluginException(this.message);

  @override
  final String message;

  @override
  String toString() => 'PluginException: $message';
}

/// Something outside the program that the engine needed and did not get: a
/// file, an external tool, a GPU device, a network service, a build artefact
/// that does not match the code reading it.
abstract base class ResourceException extends Flutter3dException {
  const ResourceException();
}

/// Something a device, a backend or a platform may or may not do, by a
/// stable [name]: a graphics device's `DeviceFeature`, a renderer's or a
/// platform's own.
///
/// **Here so that one refusal serves every layer.** [UnsupportedCapability]
/// was the hardware's alone, holding a `DeviceFeature`; the core and the
/// platforms refused what they lacked with a bare [UnsupportedError]. A
/// capability of any layer extends this and is refused the same way.
abstract base class Capability {
  const Capability();

  /// The stable identifier, used in reports, snapshots and refusals.
  String get name;

  /// Where a caller asks for this capability before calling, as code
  /// (`` `GraphicsDevice.features` ``); null when there is nowhere to ask.
  String? get askedBy => null;
}

/// The refusal every capability-gated call throws where the capability is
/// missing: a [CapabilityException] that names what was asked for and who
/// refused it.
///
/// **One type, so that a caller and the conformance suite can tell a refusal
/// the contract promised from a backend falling over.** Before 0.9 each
/// backend wrote its own sentence into a bare [UnsupportedError], and a check
/// that wanted to know whether a throw was *the* refusal had only the message
/// to go on.
///
/// **An exception and not an [UnsupportedError] since 1.0**, because a
/// caller meets it in a correct program: a device that lacks a feature is a
/// fact about the hardware, not a mistake in the code that asked. A caller
/// who asks first ([Capability.askedBy]) never sees it.
final class UnsupportedCapability extends CapabilityException {
  const UnsupportedCapability(
    this.feature, {
    required this.backend,
    this.reason,
  });

  /// What was asked for.
  final Capability feature;

  /// Who refused, as a person would name the backend.
  final String backend;

  /// Why this backend does not have it, when it can say.
  final String? reason;

  @override
  String get message =>
      '$backend does not support ${feature.name}'
      '${reason == null ? '' : ': $reason'}.'
      '${feature.askedBy == null ? '' : ' Ask whether ${feature.askedBy} has it before calling.'}';

  @override
  String toString() => 'UnsupportedCapability: $message';
}

/// A shader stage a backend's compiler refused, or a pair of stages its
/// linker would not join.
///
/// **Here, in the root's file, and not in a backend**, because every backend
/// that compiles at run time (WebGL from GLSL, WebGPU from WGSL, Impeller from
/// a bundle) meets the same failure, and a caller that reports it should not
/// have to name the backend's package to catch it. The bytes are what the
/// compiler disagreed with, so it is a [Flutter3dFormatException]: the source
/// is not the program it claims to be, at least not for this driver.
///
/// **Where, as well as what.** Besides the compiler's [log] as it was said,
/// it carries the place a tool can point at: the [stage] and the [target],
/// and the [line], [column] and [excerpt] of the first error, or every error
/// the compiler gave as [diagnostics]. All of them are optional, because a
/// driver that says nothing usable still refuses.
final class ShaderCompileException extends Flutter3dFormatException {
  const ShaderCompileException({
    required this.shader,
    required this.backend,
    required this.log,
    this.stage,
    this.target,
    this._line,
    this._column,
    this._excerpt,
    this.diagnostics = const <ShaderDiagnostic>[],
    this.cause,
  });

  /// The stage that did not compile, by the name the shader bundle gives it;
  /// for a link, both stages (`'pbr.vert with pbr.frag'`).
  final String shader;

  /// Who refused, as a person would name the backend.
  final String backend;

  /// What the compiler or the linker said, as it said it; empty when the
  /// driver said nothing.
  final String log;

  /// Which kind of stage it was (`vertex`, `fragment`, `compute`), when the
  /// backend knows; null for a link.
  final String? stage;

  /// The backend's id, as a shader bundle names its section (`webgl`,
  /// `webgpu`, `impeller`), for a tool that groups refusals by target; null
  /// when the backend did not say.
  final String? target;

  /// Every error the compiler gave, each with its own place, in the order
  /// it gave them; empty when only the [log] was read.
  final List<ShaderDiagnostic> diagnostics;

  final int? _line;
  final int? _column;
  final String? _excerpt;

  /// The line of the first error, counted from 1: the one given to the
  /// constructor, or the first of [diagnostics] that has one.
  int? get line => _line ?? _first?.line;

  /// The column of the first error, counted from 1, as for [line].
  int? get column => _column ?? _first?.column;

  /// The source line of the first error, as written, as for [line].
  String? get excerpt => _excerpt ?? _first?.excerpt;

  ShaderDiagnostic? get _first =>
      diagnostics.where((ShaderDiagnostic d) => d.line != null).firstOrNull;

  @override
  final Object? cause;

  @override
  String get message {
    final where = switch ((line, column)) {
      (null, _) => '',
      (final int l, null) => ' (line $l)',
      (final int l, final int c) => ' (line $l, column $c)',
    };
    return log.isEmpty
        ? '$backend could not compile $shader$where'
        : '$backend could not compile $shader$where:\n$log';
  }

  /// The refusal as a tool reads it: every field above, the absent ones
  /// left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'shader': shader,
    'backend': backend,
    'target': ?target,
    'stage': ?stage,
    'line': ?line,
    'column': ?column,
    'excerpt': ?excerpt,
    'log': log,
    if (diagnostics.isNotEmpty)
      'diagnostics': <Object?>[
        for (final diagnostic in diagnostics) diagnostic.toJson(),
      ],
  };

  @override
  String toString() => cause == null
      ? 'ShaderCompileException: $message'
      : 'ShaderCompileException: $message (caused by $cause)';
}

/// One error a shader compiler gave, and where: what a tool underlines.
final class ShaderDiagnostic {
  const ShaderDiagnostic(
    this.message, {
    this.stage,
    this.line,
    this.column,
    this.excerpt,
  });

  /// What the compiler said about this place, without the place.
  final String message;

  /// Which kind of stage it was in (`vertex`, `fragment`, `compute`), when
  /// known.
  final String? stage;

  /// The line, counted from 1; null when the compiler gave none.
  final int? line;

  /// The column, counted from 1; null when the compiler gave none.
  final int? column;

  /// The source line at [line], as written; null without the source.
  final String? excerpt;

  /// The errors in a compiler's [log], one per line that names a place.
  ///
  /// Reads the two shapes the engine's compilers write: GLSL's
  /// `ERROR: 0:12: message` (and Mesa's `0:12(5): error: message`), where
  /// the first number is the source string and not the line, and the
  /// `file:14:7: error: message` of glslang, Tint and Naga. With [source],
  /// each one gets its line as the [excerpt]. A log that names no place at
  /// all is one diagnostic holding the whole of it; an empty log is none.
  static List<ShaderDiagnostic> parseLog(
    String log, {
    String? stage,
    String? source,
  }) {
    final lines = source?.split('\n');
    String? excerptAt(int? line) =>
        lines == null || line == null || line < 1 || line > lines.length
        ? null
        : lines[line - 1];
    final located = <ShaderDiagnostic>[
      for (final said in log.split('\n'))
        if (_place(said.trim()) case (
          final int line,
          final int? column,
          final String message,
        ))
          ShaderDiagnostic(
            message,
            stage: stage,
            line: line,
            column: column,
            excerpt: excerptAt(line),
          ),
    ];
    if (located.isNotEmpty) return located;
    final whole = log.trim();
    return whole.isEmpty
        ? const <ShaderDiagnostic>[]
        : <ShaderDiagnostic>[ShaderDiagnostic(whole, stage: stage)];
  }

  static (int, int?, String)? _place(String said) {
    if (RegExp(r'^(?:ERROR|WARNING):\s*\d+:(\d+):\s*(.*)$').firstMatch(said)
        case final m?) {
      return (int.parse(m[1]!), null, m[2]!.trim());
    }
    if (RegExp(
          r'^\d+:(\d+)\((\d+)\):\s*(?:error|warning):\s*(.*)$',
        ).firstMatch(said)
        case final m?) {
      return (int.parse(m[1]!), int.parse(m[2]!), m[3]!.trim());
    }
    if (RegExp(
          r'^.*?:(\d+):(\d+):?\s+(?:(?:error|warning)\s*:\s*)?(.*)$',
        ).firstMatch(said)
        case final m?) {
      return (int.parse(m[1]!), int.parse(m[2]!), m[3]!.trim());
    }
    return null;
  }

  /// The diagnostic as a tool reads it, the absent fields left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'message': message,
    'stage': ?stage,
    'line': ?line,
    'column': ?column,
    'excerpt': ?excerpt,
  };

  /// The diagnostic [json] holds, as [toJson] writes it.
  ///
  /// Throws [DocumentFormatException] for anything else.
  static ShaderDiagnostic fromJson(Object? json) => switch (json) {
    {'message': final String message} => ShaderDiagnostic(
      message,
      stage: _optional<String>(json, 'stage'),
      line: _optional<int>(json, 'line'),
      column: _optional<int>(json, 'column'),
      excerpt: _optional<String>(json, 'excerpt'),
    ),
    _ => throw DocumentFormatException(
      'a shader diagnostic is a map with a "message", not $json',
    ),
  };

  static T? _optional<T>(Map<Object?, Object?> json, String key) =>
      switch (json[key]) {
        null => null,
        final T value => value,
        final other => throw DocumentFormatException(
          'a shader diagnostic\'s "$key" is a $T, not $other',
        ),
      };

  @override
  bool operator ==(Object other) =>
      other is ShaderDiagnostic &&
      other.message == message &&
      other.stage == stage &&
      other.line == line &&
      other.column == column &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(message, stage, line, column, excerpt);

  @override
  String toString() =>
      line == null ? message : '$line:${column ?? 0}: $message';
}

/// An asset the program named and the platform does not have: a key missing
/// from the Flutter asset bundle, a file not on disk.
///
/// **Thrown in place of the platform's own failure** (a `FlutterError` from
/// `rootBundle`, a `PathNotFoundException` from `dart:io`), which [cause]
/// keeps, so a caller catches one type on every platform and reads which
/// asset it was from [key] rather than from the text of somebody else's
/// message.
final class AssetNotFoundException extends ResourceException {
  const AssetNotFoundException(this.key, {this.detail, this.cause});

  /// The asset as the caller named it: a bundle key or a path.
  final String key;

  /// What else is worth saying, such as where the loader looked or how to
  /// declare the asset; null when the key says it all.
  final String? detail;

  @override
  final Object? cause;

  @override
  String get message =>
      detail == null ? 'no asset "$key"' : 'no asset "$key": $detail';

  @override
  String toString() => cause == null
      ? 'AssetNotFoundException: $message'
      : 'AssetNotFoundException: $message (caused by $cause)';
}
