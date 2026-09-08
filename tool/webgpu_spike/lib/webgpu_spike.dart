/// **A spike, not a backend.**
///
/// This package exists to answer one question with code rather than with
/// reading: is `flutter3d_hardware` a contract, or is it a description of
/// OpenGL's conventions wearing neutral names? It answers by implementing
/// enough of that contract on WebGPU — a top-left, zero-to-one, framebuffer-wound
/// API that agrees with OpenGL about almost nothing — to draw one triangle and
/// read it back, and then counting what had to change to get there.
///
/// **Nothing here is a fourth backend and nothing here is on its way to
/// becoming one.** It loads no bundle, binds no uniform block, samples no
/// texture, presents no frame and passes none of `flutter3d_conformance`. Every
/// member that throws says which of two things it is — ordinary work the spike
/// did not do, or a point where the contract and the API do not meet — and the
/// second kind names its entry in [webgpuContractGaps]. That list is the
/// deliverable; the triangle is what makes it trustworthy.
///
/// **This half is pure Dart and runs on the VM**: the translation tables, the
/// pipeline key and the gap list. The half that touches a browser is
/// `webgpu_spike_web.dart`, and it is separate so that the answers this package
/// exists to give can be asserted without a GPU.
///
/// See `README.md` beside this file for the count and for why the package lives
/// under `tool/`.
library;

export 'src/webgpu_contract_gaps.dart';
export 'src/webgpu_conventions.dart';
