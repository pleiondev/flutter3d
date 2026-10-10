/// The words `.f3dproj`, the command journal and a command's arguments write
/// for the Dart enums they hold, and back.
///
/// **Explicit, so a rename cannot change a file** (CONTRACTS.md, "Words
/// written to a file come from explicit wire tables"). These keys used to be
/// written with a value's `.name` and read back by comparing `.name`; the day
/// an identifier was renamed, every project saved before would have opened
/// with that field downgraded to its default, and every one saved after
/// would say something a released build does not know. Each table holds the
/// words as they were on the day `.f3dproj` went 1.0; a value renamed in Dart
/// keeps its word here, and a value added gets a new one.
///
/// Every writer is an exhaustive `switch`, so a new case does not compile
/// until it has a word. Every reader answers null for a word it does not
/// know, and the caller says what that means: a fallback with a warning in
/// a project, a skipped entry in a journal.
library;

import 'package:flutter3d_core/formats.dart'
    show AnimationInterpolation, AnimationPath, SurfaceAlphaMode, TextureWrap;
import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show CsgOperation, ElementLevel;

import 'command.dart' show TransformPivot, TransformSpace;
import 'history.dart' show StepAuthor;
import 'project.dart' show ProfileTarget;
import 'selection.dart' show SelectionMode;
import 'texture_graph.dart' show TextureBlendMode, TextureChannel;
import 'texture_info.dart' show TextureFileFormat;

/// A history step's and a journal line's `author`.
String stepAuthorWord(StepAuthor author) => switch (author) {
  StepAuthor.person => 'person',
  StepAuthor.agent => 'agent',
};

/// The [StepAuthor] [word] names, or null.
StepAuthor? stepAuthorOf(Object? word) => switch (word) {
  'person' => StepAuthor.person,
  'agent' => StepAuthor.agent,
  _ => null,
};

/// A profile's `target`.
String profileTargetWord(ProfileTarget target) => switch (target) {
  ProfileTarget.desktop => 'desktop',
  ProfileTarget.mobile => 'mobile',
  ProfileTarget.web => 'web',
};

/// The [ProfileTarget] [word] names, or null.
ProfileTarget? profileTargetOf(Object? word) => switch (word) {
  'desktop' => ProfileTarget.desktop,
  'mobile' => ProfileTarget.mobile,
  'web' => ProfileTarget.web,
  _ => null,
};

/// A texture budget's `targetFormat`.
String textureFileFormatWord(TextureFileFormat format) => switch (format) {
  TextureFileFormat.rgba8 => 'rgba8',
  TextureFileFormat.bc1 => 'bc1',
  TextureFileFormat.bc3 => 'bc3',
  TextureFileFormat.bc7 => 'bc7',
  TextureFileFormat.etc2Rgba8 => 'etc2Rgba8',
  TextureFileFormat.astc4x4 => 'astc4x4',
  TextureFileFormat.other => 'other',
};

/// The [TextureFileFormat] [word] names, or null.
TextureFileFormat? textureFileFormatOf(Object? word) => switch (word) {
  'rgba8' => TextureFileFormat.rgba8,
  'bc1' => TextureFileFormat.bc1,
  'bc3' => TextureFileFormat.bc3,
  'bc7' => TextureFileFormat.bc7,
  'etc2Rgba8' => TextureFileFormat.etc2Rgba8,
  'astc4x4' => TextureFileFormat.astc4x4,
  'other' => TextureFileFormat.other,
  _ => null,
};

/// A material's `alphaMode`.
String alphaModeWord(SurfaceAlphaMode mode) => switch (mode) {
  SurfaceAlphaMode.opaque => 'opaque',
  SurfaceAlphaMode.mask => 'mask',
  SurfaceAlphaMode.blend => 'blend',
};

/// The [SurfaceAlphaMode] [word] names, or null.
SurfaceAlphaMode? alphaModeOf(Object? word) => switch (word) {
  'opaque' => SurfaceAlphaMode.opaque,
  'mask' => SurfaceAlphaMode.mask,
  'blend' => SurfaceAlphaMode.blend,
  _ => null,
};

/// A sampler's `wrapS` and `wrapT`.
String textureWrapWord(TextureWrap wrap) => switch (wrap) {
  TextureWrap.repeat => 'repeat',
  TextureWrap.clampToEdge => 'clampToEdge',
  TextureWrap.mirroredRepeat => 'mirroredRepeat',
};

/// The [TextureWrap] [word] names, or null.
TextureWrap? textureWrapOf(Object? word) => switch (word) {
  'repeat' => TextureWrap.repeat,
  'clampToEdge' => TextureWrap.clampToEdge,
  'mirroredRepeat' => TextureWrap.mirroredRepeat,
  _ => null,
};

/// A selection's `mode`.
String selectionModeWord(SelectionMode mode) => switch (mode) {
  SelectionMode.object => 'object',
  SelectionMode.mesh => 'mesh',
};

/// The [SelectionMode] [word] names, or null.
SelectionMode? selectionModeOf(Object? word) => switch (word) {
  'object' => SelectionMode.object,
  'mesh' => SelectionMode.mesh,
  _ => null,
};

/// A selection's `level`.
String elementLevelWord(ElementLevel level) => switch (level) {
  ElementLevel.vertex => 'vertex',
  ElementLevel.edge => 'edge',
  ElementLevel.face => 'face',
};

/// The [ElementLevel] [word] names, or null.
ElementLevel? elementLevelOf(Object? word) => switch (word) {
  'vertex' => ElementLevel.vertex,
  'edge' => ElementLevel.edge,
  'face' => ElementLevel.face,
  _ => null,
};

/// A blend texture node's `mode`.
String textureBlendModeWord(TextureBlendMode mode) => switch (mode) {
  TextureBlendMode.normal => 'normal',
  TextureBlendMode.multiply => 'multiply',
  TextureBlendMode.add => 'add',
  TextureBlendMode.screen => 'screen',
};

/// The [TextureBlendMode] [word] names, or null.
TextureBlendMode? textureBlendModeOf(Object? word) => switch (word) {
  'normal' => TextureBlendMode.normal,
  'multiply' => TextureBlendMode.multiply,
  'add' => TextureBlendMode.add,
  'screen' => TextureBlendMode.screen,
  _ => null,
};

/// A channels texture node's `channel`.
String textureChannelWord(TextureChannel channel) => switch (channel) {
  TextureChannel.r => 'r',
  TextureChannel.g => 'g',
  TextureChannel.b => 'b',
  TextureChannel.a => 'a',
};

/// The [TextureChannel] [word] names, or null.
TextureChannel? textureChannelOf(Object? word) => switch (word) {
  'r' => TextureChannel.r,
  'g' => TextureChannel.g,
  'b' => TextureChannel.b,
  'a' => TextureChannel.a,
  _ => null,
};

/// A transform command's `pivot`.
String transformPivotWord(TransformPivot pivot) => switch (pivot) {
  TransformPivot.median => 'median',
  TransformPivot.individual => 'individual',
};

/// The [TransformPivot] [word] names, or null.
TransformPivot? transformPivotOf(Object? word) => switch (word) {
  'median' => TransformPivot.median,
  'individual' => TransformPivot.individual,
  _ => null,
};

/// A transform command's `space`.
String transformSpaceWord(TransformSpace space) => switch (space) {
  TransformSpace.global => 'global',
  TransformSpace.local => 'local',
};

/// The [TransformSpace] [word] names, or null.
TransformSpace? transformSpaceOf(Object? word) => switch (word) {
  'global' => TransformSpace.global,
  'local' => TransformSpace.local,
  _ => null,
};

/// A keyed track's `path`.
String animationPathWord(AnimationPath path) => switch (path) {
  AnimationPath.translation => 'translation',
  AnimationPath.rotation => 'rotation',
  AnimationPath.scale => 'scale',
  AnimationPath.weights => 'weights',
  AnimationPath.pointer => 'pointer',
};

/// The [AnimationPath] [word] names, or null.
AnimationPath? animationPathOf(Object? word) => switch (word) {
  'translation' => AnimationPath.translation,
  'rotation' => AnimationPath.rotation,
  'scale' => AnimationPath.scale,
  'weights' => AnimationPath.weights,
  'pointer' => AnimationPath.pointer,
  _ => null,
};

/// A keyed track's `interpolation`.
String interpolationWord(AnimationInterpolation interpolation) =>
    switch (interpolation) {
      AnimationInterpolation.step => 'step',
      AnimationInterpolation.linear => 'linear',
      AnimationInterpolation.cubicSpline => 'cubicSpline',
    };

/// The [AnimationInterpolation] [word] names, or null.
AnimationInterpolation? interpolationOf(Object? word) => switch (word) {
  'step' => AnimationInterpolation.step,
  'linear' => AnimationInterpolation.linear,
  'cubicSpline' => AnimationInterpolation.cubicSpline,
  _ => null,
};

/// A boolean modifier's `operation`.
String csgOperationWord(CsgOperation operation) => switch (operation) {
  CsgOperation.union => 'union',
  CsgOperation.subtract => 'subtract',
  CsgOperation.intersect => 'intersect',
};

/// The [CsgOperation] [word] names, or null.
CsgOperation? csgOperationOf(Object? word) => switch (word) {
  'union' => CsgOperation.union,
  'subtract' => CsgOperation.subtract,
  'intersect' => CsgOperation.intersect,
  _ => null,
};
