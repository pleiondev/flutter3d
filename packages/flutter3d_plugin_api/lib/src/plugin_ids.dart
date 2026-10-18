/// The ids the engine's own plugins had before 1.0.0, and what readers make
/// of them. Not exported: the readers of this package use it, nobody else.
library;

/// The engine's plugin ids from before they were named after their
/// packages, each to the id it has now.
///
/// **Why a reader lifts them.** A run, a network hello or a `.f3dplugin`
/// that a build from before 1.0.0 wrote names its plugins by these, and a
/// replay of it asks this engine to install them. The add-on packages they
/// are named after were never published; `flutter3d_audio` is the SoLoud
/// package, whose plugin was `flutter3d_audio_core`'s all along. No plugin
/// may take one of the add-ons' namespaces (`PluginManifest.idProblem`), so
/// a lifted id is never somebody else's.
const Map<String, String> renamedPluginIds = <String, String>{
  'flutter3d_addon_access.spoken_events': 'flutter3d_game_ui.spoken_events',
  'flutter3d_addon_atmosphere.fog': 'flutter3d_post.fog',
  'flutter3d_addon_atmosphere.light_shafts': 'flutter3d_post.light_shafts',
  'flutter3d_addon_atmosphere.sky': 'flutter3d_post.sky',
  'flutter3d_addon_atmosphere.volumetric_fog': 'flutter3d_post.volumetric_fog',
  'flutter3d_addon_camera': 'flutter3d_camera',
  'flutter3d_addon_light.auto_exposure': 'flutter3d_post.auto_exposure',
  'flutter3d_addon_light.bloom': 'flutter3d_post.bloom',
  'flutter3d_addon_light.colour_grade': 'flutter3d_post.color_grade',
  'flutter3d_addon_light.lens_distortion': 'flutter3d_post.lens_distortion',
  'flutter3d_addon_light.lens_flare': 'flutter3d_post.lens_flare',
  'flutter3d_addon_light.local_exposure': 'flutter3d_post.local_exposure',
  'flutter3d_addon_light.vignette_and_grain':
      'flutter3d_post.vignette_and_grain',
  'flutter3d_addon_motion.depth_of_field': 'flutter3d_post.depth_of_field',
  'flutter3d_addon_motion.motion_blur': 'flutter3d_post.motion_blur',
  'flutter3d_addon_motion.temporal_anti_aliasing':
      'flutter3d_post.temporal_anti_aliasing',
  'flutter3d_addon_reactions': 'flutter3d_game_kit.reactions',
  'flutter3d_addon_reflections.planar': 'flutter3d_post.planar_reflections',
  'flutter3d_addon_reflections.probes': 'flutter3d_post.reflection_probes',
  'flutter3d_addon_reflections.screen_space':
      'flutter3d_post.screen_space_reflections',
  'flutter3d_addon_shading.ambient_occlusion':
      'flutter3d_post.ambient_occlusion',
  'flutter3d_addon_shading.contact_shadows': 'flutter3d_post.contact_shadows',
  'flutter3d_addon_soundtrack': 'flutter3d_game_kit.soundtrack',
  'flutter3d_addon_style.high_contrast': 'flutter3d_post.high_contrast',
  'flutter3d_addon_style.outlines': 'flutter3d_post.outlines',
  'flutter3d_addon_style.toon': 'flutter3d_post.toon',
  'flutter3d_addon_style.viewport_shading': 'flutter3d_post.viewport_shading',
  'flutter3d_audio': 'flutter3d_audio_core',
};

/// The namespaces of the old ids that no plugin may take, since a reader
/// lifts ids in them: the add-ons', which nobody holds on pub.dev.
/// `flutter3d_audio` is the engine's own namespace and stays usable.
final Set<String> retiredPluginNamespaces = <String>{
  for (final id in renamedPluginIds.keys)
    if (id.startsWith('flutter3d_addon_'))
      id.contains('.') ? id.substring(0, id.indexOf('.')) : id,
};

/// [id] as this release names it.
String liftPluginId(String id) => renamedPluginIds[id] ?? id;

/// A `dependsOn` entry, `'id'` or `'id <range>'`, with its id lifted.
String liftPluginDependency(String entry) {
  final space = entry.indexOf(' ');
  return space < 0
      ? liftPluginId(entry)
      : '${liftPluginId(entry.substring(0, space))}${entry.substring(space)}';
}
