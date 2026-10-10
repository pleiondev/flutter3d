/// Compute kernels written in `.f3dmat compute`, read once and translated
/// for each placement: WGSL for WebGPU and the wgpu sidecar, a Dart kernel
/// for the CPU — 1.0.
///
/// **Pure Dart, with no `dart:io`**, so a backend in a browser, a build
/// hook and a test read it alike. A device with compute loads a bundle's
/// kernel section through [kernelsOf] and translates what it finds; a
/// caller that wants a bundle of its own kernels makes one with
/// [kernelBundle].
library;

export 'src/compute_kernel.dart';
