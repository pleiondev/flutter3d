/// What a device says when it cannot make, read or open something — the two
/// [ResourceException] leaves of the HAL.
///
/// **Thrown, not answered with null, since 1.0** (decision 4 of the API
/// review). The creators and the readback used to return null for "the
/// device would not", and a null travels: it reached a material as a missing
/// texture and a frame as a black square, a long way from the call that
/// declined. A throw names the call, the backend and the reason where it
/// happened, and a caller that can carry on catches it there.
///
/// A device that lacks a *feature* throws `UnsupportedCapability`, a
/// `CapabilityException`, as it always has; these two are for a request the
/// device has the feature for and still cannot honour.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

/// A resource a device was asked to make or read and could not: pixels that
/// are not the size their description says, a texture with nothing to read.
final class DeviceResourceException extends ResourceException {
  const DeviceResourceException({
    required this.operation,
    required this.backend,
    required this.reason,
    this.cause,
  });

  /// The call that refused, as `GraphicsDevice` names it
  /// (`createTextureFromPixels`, `readback`).
  final String operation;

  /// Who refused, as a person would name the backend.
  final String backend;

  /// Why, in a sentence that names what was wrong with the request.
  final String reason;

  @override
  final Object? cause;

  @override
  String get message => '$backend refused $operation: $reason';

  @override
  String toString() => cause == null
      ? 'DeviceResourceException: $message'
      : 'DeviceResourceException: $message (caused by $cause)';
}

/// A device that would not open: a browser without WebGL2 or WebGPU, a GPU
/// the browser has blocklisted, or every backend a `DeviceRegistry` holds
/// refusing in turn.
final class DeviceUnavailableException extends ResourceException {
  const DeviceUnavailableException(
    this.message, {
    this.backend,
    this.refusals = const <String>[],
    this.cause,
  });

  @override
  final String message;

  /// The backend that would not open; null when the refusal is a
  /// registry's, which tried several.
  final String? backend;

  /// What each backend a registry tried said, in the order it tried them —
  /// empty for a single backend's refusal, and for a registry nothing was
  /// added to.
  final List<String> refusals;

  @override
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DeviceUnavailableException: $message'
      : 'DeviceUnavailableException: $message (caused by $cause)';
}
