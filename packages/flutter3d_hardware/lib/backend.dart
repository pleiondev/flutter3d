/// What a graphics backend needs beyond the contract in
/// `flutter3d_hardware.dart`: the constructors of the handles it hands out.
///
/// **For the author of a `GraphicsDevice`, not for an application.** A
/// handle's constructor is private since 1.0, so code that draws cannot make
/// a texture or a pipeline that no device made; a backend wraps its own
/// objects with these, naming itself as the owner so that the handle's
/// `dispose` gives the object back to it.
library;

export 'src/backend_handles.dart';
