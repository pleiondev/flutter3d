/// A graphics backend that draws nothing and remembers everything.
///
/// The counterpart to the fake texture source in `frame_resources_test.dart`,
/// and it exists for the same reason. Every type a pass used to name —
/// `gpu.RenderPass`, `gpu.HostBuffer`, `gpu.Shader`, `gpu.RenderPipeline` —
/// needed a live device to construct, so nothing that *encoded* anything could
/// be tested at all. What a node draws was checked by looking at a golden image
/// twelve minutes later, or not at all.
///
/// With the backend arriving as a value, a node can be handed one of these and
/// asked what it did: which passes it opened, what they were attached to, what
/// state it left them in, what it bound and how many times it drew.
///
/// ## Why it is in `lib/`, and in this package
///
/// **It was four hundred and seventy-five lines in two copies, and they had
/// already drifted.** `flutter3d/test/fake_backend.dart` and
/// `flutter3d_particles/test/fake_backend.dart` were the same file down to the
/// paragraph above — which still names a test that only exists in one of them —
/// and the particles copy was twenty-six lines behind: no `pendingFrames`, no
/// `completesImmediately`, no `uploadedPixels`. A test written against it could
/// not ask the question those exist to answer, and nothing said so.
///
/// This package rather than a new one, because that is what it depends on:
/// `flutter3d_hardware` and `flutter/widgets`, and nothing else. A separate
/// `flutter3d_fakes` would be a twenty-second workspace entry holding one file.
///
/// In `lib/` rather than in a shared `test/`, because a package cannot import
/// another package's `test/` — which is the reason there were two copies.
///
/// ```dart
/// import 'package:flutter3d_hardware/testing.dart';
/// ```
///
/// [Recorded] and its subclasses — one entry per thing a pass was told to do —
/// are `src/testing_recorded.dart`. [FakePass], the [CommandEncoder] that
/// records them, is `src/testing_fake_pass.dart`. [FakeShaderLibrary] and
/// [FakeBackend], the [GraphicsDevice] that opens one, are
/// `src/testing_fake_backend.dart`. All three are re-exported from here.
library;

export 'src/testing_fake_backend.dart';
export 'src/testing_fake_pass.dart';
export 'src/testing_recorded.dart';
