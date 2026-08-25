import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// Where a frame's textures come from, and where they go back to.
///
/// An interface rather than a [RenderTargetPool] because **a texture cannot go
/// straight back to the pool when the last pass stops reading it.** The GPU is
/// still working through this frame's command buffers; handing the texture
/// back immediately lets the pool lend it to the next acquirer while the
/// hardware is reading it, and the result is an intermittent wrong picture —
/// the hardest kind of defect to trace back to its cause.
///
/// The renderer already knew this and defers releases by a full ring of frames
/// in flight. `FrameResources` released straight to the pool until the shadow
/// passes were read closely enough to notice, which is the argument for
/// reading working code before replacing it.
abstract interface class FrameTextureSource {
  TextureHandle acquire(RenderTargetSpec spec);

  /// Gives a texture up. The implementation decides *when* it is safe to reuse.
  void release(TextureHandle texture);
}

/// A source that returns textures to the pool at once.
///
/// For tests and for anything that is not inside a frame in flight. Using this
/// from a renderer is the bug described on [FrameTextureSource].
final class ImmediateTextureSource implements FrameTextureSource {
  const ImmediateTextureSource(this.pool);

  final RenderTargetPool pool;

  @override
  TextureHandle acquire(RenderTargetSpec spec) => pool.acquire(spec);

  @override
  void release(TextureHandle texture) => pool.release(texture);
}
