/// What a graphics backend needs beyond the contract in
/// `flutter3d_hardware.dart`: the constructors of the handles it hands out,
/// and the check it makes before it uses one.
///
/// **For the author of a `GraphicsDevice`, not for an application.** A
/// handle's constructor is private since 1.0, so code that draws cannot make
/// a texture or a pipeline that no device made; a backend wraps its own
/// objects with these, naming itself as the owner so that the handle's
/// `dispose` gives the object back to it, and calls `debugCheckLive` before
/// handing a handle it was given to its API. A backend that can read a
/// buffer in the calling turn mixes in `SynchronousBufferReadback` from
/// here; a caller that asks for it imports it from `testing.dart`, since
/// the main library does not offer a stall.
/// [UniformScratch] is the buffer a backend fills a uniform block in, kept
/// per block size instead of made per draw.
///
/// **As stable as the contract itself.** This library is part of the
/// package's snapshot and follows the same strict semver through 1.x: a
/// constructor here gains only optional parameters within a major, and a new
/// kind of handle arrives as a new constructor. A backend written against
/// 1.0.0 keeps compiling against every 1.x.
library;

export 'src/backend_handles.dart';
export 'src/compute_checks.dart';
export 'src/handle_checks.dart';
export 'src/synchronous_readback.dart';
export 'src/uniform_scratch.dart';
