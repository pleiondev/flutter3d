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

/// A shader stage a backend's compiler refused, or a pair of stages its
/// linker would not join.
///
/// **Here, in the root's file, and not in a backend**, because every backend
/// that compiles at run time (WebGL from GLSL, WebGPU from WGSL, Impeller from
/// a bundle) meets the same failure, and a caller that reports it should not
/// have to name the backend's package to catch it. The bytes are what the
/// compiler disagreed with, so it is a [Flutter3dFormatException]: the source
/// is not the program it claims to be, at least not for this driver.
final class ShaderCompileException extends Flutter3dFormatException {
  const ShaderCompileException({
    required this.shader,
    required this.backend,
    required this.log,
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

  @override
  final Object? cause;

  @override
  String get message => log.isEmpty
      ? '$backend could not compile $shader'
      : '$backend could not compile $shader:\n$log';

  @override
  String toString() => cause == null
      ? 'ShaderCompileException: $message'
      : 'ShaderCompileException: $message (caused by $cause)';
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
