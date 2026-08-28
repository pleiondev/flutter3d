/// The test models, as the two paths anything needs to reach them.
///
/// There is no code here on purpose. What a fixture package owes its callers is
/// where the files are, said once, so that a path typed out in fourteen places
/// cannot be typed out fifteen different ways — which is what happened to the
/// old `'assets/samples'` constant, copied into six test files and one demo.
///
/// **Two paths and not one, because a file on disk and an asset in a bundle are
/// different things.** A test reads bytes with `dart:io` and wants a directory
/// relative to the package it runs in; a widget asks an `AssetBundle` and wants
/// the `packages/<name>/…` key Flutter registers. Neither can be derived from
/// the other at run time.
library;

/// The prefix an [AssetBundle] key starts with, for anything drawing these
/// models in a running application.
///
///     rootBundle.load('$kSamplesAsset/BoxTextured.glb')
const String kSamplesAsset = 'packages/flutter3d_samples/assets';

/// Where the files are on disk, relative to a sibling package's directory.
///
/// For tests and command-line tools, which read the bytes themselves rather
/// than through a bundle. It is relative rather than absolute because that is
/// what a test's working directory — the package being tested — makes usable,
/// and it holds for every package in this workspace since they are all siblings
/// under `packages/`.
///
/// A consumer who installed this package from pub has these files inside the
/// package archive rather than beside their own, and reaches them through
/// [kSamplesAsset] or through their own resolution of `package:` URIs. The
/// tests that use the constant below are ours and do not ship runnable.
const String kSamplesPath = '../flutter3d_samples/assets';
