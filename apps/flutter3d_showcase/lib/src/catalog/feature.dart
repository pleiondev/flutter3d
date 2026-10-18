/// What the showcase knows about a capability, as plain values.
///
/// **No Flutter import, on purpose.** `tool/showcase_bundle.dart` reads the
/// catalog with a plain `dart run` to write the pages of the documentation
/// site, and the structure rules read it the same way. A catalog that could
/// only be read by a running app would leave the site with a second list to
/// keep in step with this one.
library;

/// Which part of the engine a page belongs to, and the directory its files
/// live in.
enum Category {
  /// Materials, lights and how a surface takes light.
  shading('shading', 'Shading and materials'),

  /// Skies, image-based lighting, fog and the light that bounces.
  environment('environment', 'Light and environment'),

  /// Each kind of shadow map and the settings that tune it.
  shadows('shadows', 'Shadows'),

  /// The passes that run on the finished frame.
  post('post', 'Post-processing'),

  /// Nodes, meshes, instances, culling and what a frame reports.
  scene('scene', 'Scene and geometry'),

  /// Skinning, morph targets, clips, layers and IK.
  animation('animation', 'Animation'),

  /// Cameras, projections, picking and input.
  viewInput('view_input', 'Views, picking and input'),

  /// The files the engine reads, writes and converts.
  formats('formats', 'Formats and I/O'),

  /// The backends the same scene runs on, and what differs between them.
  backends('backends', 'Backends'),

  /// Bodies, joints, cloth and particle systems.
  physicsParticles('physics_particles', 'Physics and particles'),

  /// The simulation and its gameplay systems, positional audio and stereo.
  simAudioXr('sim_audio_xr', 'Simulation, audio and XR'),

  /// The widgets, saves, tooling and whatever fits no other category.
  widgetsMisc('widgets_misc', 'Widgets and the rest'),

  /// A Flame game and a flutter3d scene in one widget tree.
  flame('flame', 'The Flame bridge');

  const Category(this.dir, this.title);

  /// The directory under `lib/pages/`, and the key a page is looked up by.
  final String dir;

  /// The heading the navigation tree and the site give the category.
  final String title;
}

/// What a page asks of the graphics device.
///
/// One to one with the `DeviceFeature`s `CapabilityReport.of` reads off
/// `GraphicsDevice.features`, because a badge that named a backend would be
/// wrong the day a backend learns the feature; a badge that names the
/// capability is right on every one of them.
enum Need {
  /// Lines drawn along the triangles' edges, `DeviceFeature.wireframe`.
  wireframe('wireframe'),

  /// Six-faced textures sampled by direction, `DeviceFeature.cubeTextures`.
  cubeTextures('cube textures'),

  /// A texture whose smaller copies the page writes itself,
  /// `DeviceFeature.manualMipmaps`.
  mipmaps('mip maps'),

  /// A pass that draws into one mip level of a texture,
  /// `DeviceFeature.renderToMipLevel`.
  renderToMip('rendering into a mip level'),

  /// A stencil attachment to test and write, `DeviceFeature.stencil`.
  stencil('a stencil buffer'),

  /// A constant colour the blend equation can read,
  /// `DeviceFeature.blendConstant`.
  blendColor('a blend constant'),

  /// A multisampled colour target that is not the screen,
  /// `DeviceFeature.offscreenMultisample`.
  offscreenMsaa('multisampled off-screen targets');

  const Need(this.label);

  /// The capability in words, as the sentence "this device has no …" says it.
  final String label;
}

/// A later release that changed what a page shows, after the one it arrived in.
///
/// **Read from a CHANGELOG the same way [Feature.since] is.** [evidence] is
/// words the section `## version` of [evidenceFile] actually has, and the
/// catalog test looks for them there, so the site's list of what changed in a
/// release cannot say something the record does not.
final class Change {
  /// A change in [version], said by [note] and proved by [evidence] in
  /// [evidenceFile], which is the core's CHANGELOG unless a page names another.
  const Change({
    required this.version,
    required this.note,
    required this.evidence,
    this.evidenceFile = 'packages/flutter3d_core/CHANGELOG.md',
  });

  /// The release, `0.7.4`.
  final String version;

  /// One sentence for the site's changelog, in the page's own terms.
  final String note;

  /// Words that section `## [version]` of [evidenceFile] has verbatim; the
  /// catalog test fails when it does not.
  final String evidence;

  /// The CHANGELOG [evidence] is looked for in, from the repository root.
  final String evidenceFile;

  /// The change as the site's generator writes it into the catalog's JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'note': note,
    'evidence': evidence,
    'evidenceFile': evidenceFile,
  };
}

/// One capability of the engine: one page, one guide, one version tag.
final class Feature {
  /// A page's entry. Its version tag is checked against [evidence] in
  /// [evidenceFile], the facade's CHANGELOG unless the page names another,
  /// and it runs anywhere unless [needs] says what it asks of the device.
  const Feature({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.since,
    required this.evidence,
    this.evidenceFile = 'packages/flutter3d/CHANGELOG.md',
    this.approximate = false,
    this.keywords = const <String>[],
    this.packages = const <String>['flutter3d'],
    this.engineFiles = const <String>[],
    this.needs = const <Need>{},
    this.changes = const <Change>[],
  });

  /// Kebab-case and never changed: it is the address of the page, the name of
  /// its two files and of its picture.
  final String id;

  /// The page's name in the navigation tree, its heading and the site's.
  final String title;

  /// The part of the engine the page belongs to, and so the directory under
  /// `lib/pages/` its files are in.
  final Category category;

  /// One sentence, in the words a person who has not read the engine would
  /// use.
  final String summary;

  /// The version this capability first appeared in, `0.4.3`; `0.7.0` while it
  /// is unreleased.
  final String since;

  /// A piece of text the CHANGELOG says under the heading of [since]. The
  /// catalog test looks for it there and nowhere else, so the tag cannot
  /// drift from the record it is read from.
  final String evidence;

  /// The CHANGELOG [evidence] is looked for in, from the repository root.
  final String evidenceFile;

  /// Whether [since] is a bound rather than a date: the earliest place the
  /// record mentions the capability, with no entry that says it arrived. The
  /// page then reads "since 0.5.1 or earlier".
  final bool approximate;

  /// Words the record would use for this capability, for the check that no
  /// older section already mentions it.
  final List<String> keywords;

  /// The packages the capability comes from, which the site lists on the page.
  final List<String> packages;

  /// Files in the engine that implement it, so a page can point at them and a
  /// test can notice one that moved.
  final List<String> engineFiles;

  /// What the page asks of the device; one it lacks puts a badge over the
  /// demo saying which part will not show.
  final Set<Need> needs;

  /// The releases after [since] that changed what this page shows, oldest
  /// first. The site's changelog lists a page under each of them.
  final List<Change> changes;

  /// The stem of the page's files.
  String get stem => id.replaceAll('-', '_');

  /// `lib/pages/shading/pbr_lighting`, without an extension.
  String get pagePath => 'lib/pages/${category.dir}/$stem';

  /// The page's demo, from the app's root: the file the Source tab shows.
  String get pageFile => '$pagePath.dart';

  /// The page's step-by-step guide beside its demo, from the app's root.
  String get tutorialFile => '$pagePath.md';

  /// The page as the site's generator writes it into the catalog's JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'category': category.dir,
    'categoryTitle': category.title,
    'summary': summary,
    'since': since,
    'approximate': approximate,
    'evidence': evidence,
    'evidenceFile': evidenceFile,
    'packages': packages,
    'needs': <String>[for (final Need need in needs) need.name],
    'pageFile': pageFile,
    'tutorialFile': tutorialFile,
    'changes': <Map<String, Object?>>[
      for (final Change change in changes) change.toJson(),
    ],
  };
}

/// Compares two `major.minor.patch` version strings, the way semver orders
/// them.
///
/// Numeric, not textual: `0.10.0` comes after `0.9.0`. Anything after a `+`
/// is ignored, since a build number does not say when a capability arrived.
/// A pre-release after a `-` is not: `1.0.0-rc.1` comes before `1.0.0`, and
/// read as `1.0.0` it would be the same release as the one it precedes.
int compareVersions(String a, String b) {
  (List<int>, List<String>) parts(String version) {
    final String core = version.split('+').first;
    final int dash = core.indexOf('-');
    final String release = dash < 0 ? core : core.substring(0, dash);
    return (
      <int>[for (final String p in release.split('.')) int.tryParse(p) ?? 0],
      dash < 0 ? const <String>[] : core.substring(dash + 1).split('.'),
    );
  }

  int identifier(String l, String r) =>
      switch ((int.tryParse(l), int.tryParse(r))) {
        (final int x, final int y) => x.compareTo(y),
        (int(), null) => -1,
        (null, int()) => 1,
        _ => l.compareTo(r),
      };

  final (List<int> x, List<String> xPre) = parts(a);
  final (List<int> y, List<String> yPre) = parts(b);
  for (var i = 0; i < 3; i++) {
    final int left = i < x.length ? x[i] : 0;
    final int right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  if (xPre.isEmpty || yPre.isEmpty) {
    return (xPre.isEmpty ? 1 : 0) - (yPre.isEmpty ? 1 : 0);
  }
  for (var i = 0; i < xPre.length && i < yPre.length; i++) {
    final int c = identifier(xPre[i], yPre[i]);
    if (c != 0) return c;
  }
  return xPre.length.compareTo(yPre.length);
}
