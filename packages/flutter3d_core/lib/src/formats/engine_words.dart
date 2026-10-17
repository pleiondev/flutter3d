/// How the engine's own anchors, resources and steps were spelled before
/// they carried `f3d.`, and the word each is now.
library;

/// The name [written] reads as: the engine's `f3d.<name>` for a word from
/// before the prefix (`after bloom` is `f3d.after_bloom`, `scene_color` is
/// `f3d.scene_color`, `hi-z occlusion` is `f3d.hi_z_occlusion`), and
/// [written] itself for anything with a dot in it.
///
/// **Mechanical, and exact for every file written before the prefix.**
/// A plugin's name has always carried its namespace and a dot
/// (`PluginManifest.nameProblem` refuses one without), and the engine's
/// never did, so a word without a dot is the engine's, and the new word is
/// the old one with its spaces and dashes made underscores. Already-new
/// words pass through, so lifting a document twice changes nothing.
String engineWordFor(String written) => written.contains('.')
    ? written
    : 'f3d.${written.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}';
