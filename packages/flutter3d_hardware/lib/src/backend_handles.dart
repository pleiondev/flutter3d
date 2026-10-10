/// The handle constructors, for a backend's implementation of
/// `GraphicsDevice`. Exported by `package:flutter3d_hardware/backend.dart`
/// and by nothing an application imports: a device hands handles out, and
/// nothing else makes one.
library;

export 'compute.dart' show wrapComputePipeline, wrapStorageBuffer;
export 'geometry_buffer.dart' show wrapGeometry;
export 'resources.dart' show wrapQuerySet, wrapRenderBundle;
export 'shader.dart' show forgetShader, wrapPipeline, wrapShader;
export 'texture.dart' show wrapTexture;
