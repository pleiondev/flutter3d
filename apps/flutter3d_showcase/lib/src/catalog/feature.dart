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
  shading('shading', 'Shading and materials'),
  environment('environment', 'Light and environment'),
  shadows('shadows', 'Shadows'),
  post('post', 'Post-processing'),
  scene('scene', 'Scene and geometry'),
  animation('animation', 'Animation'),
  viewInput('view_input', 'Views, picking and input'),
  formats('formats', 'Formats and I/O'),
  backends('backends', 'Backends'),
  physicsParticles('physics_particles', 'Physics and particles'),
  simAudioXr('sim_audio_xr', 'Simulation, audio and XR'),
  widgetsMisc('widgets_misc', 'Widgets and the rest');

  const Category(this.dir, this.title);

  /// The directory under `lib/pages/`, and the key a page is looked up by.
  final String dir;
  final String title;
}

/// What a page asks of the graphics device.
///
/// One to one with the `supports*` getters of `GraphicsDevice`, because a
/// badge that named a backend would be wrong the day a backend learns the
/// feature; a badge that names the capability is right on every one of them.
enum Need {
  wireframe('wireframe'),
  cubeTextures('cube textures'),
  mipmaps('mip maps'),
  renderToMip('rendering into a mip level'),
  stencil('a stencil buffer'),
  blendColor('a blend constant'),
  offscreenMsaa('multisampled off-screen targets');

  const Need(this.label);
  final String label;
}

/// One capability of the engine: one page, one guide, one version tag.
final class Feature {
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
  });

  /// Kebab-case and never changed: it is the address of the page, the name of
  /// its two files and of its picture.
  final String id;
  final String title;
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
  final String evidenceFile;

  /// Whether [since] is a bound rather than a date: the earliest place the
  /// record mentions the capability, with no entry that says it arrived. The
  /// page then reads "since 0.5.1 or earlier".
  final bool approximate;

  /// Words the record would use for this capability, for the check that no
  /// older section already mentions it.
  final List<String> keywords;
  final List<String> packages;

  /// Files in the engine that implement it, so a page can point at them and a
  /// test can notice one that moved.
  final List<String> engineFiles;
  final Set<Need> needs;

  /// The stem of the page's files.
  String get stem => id.replaceAll('-', '_');

  /// `lib/pages/shading/pbr_lighting`, without an extension.
  String get pagePath => 'lib/pages/${category.dir}/$stem';
  String get pageFile => '$pagePath.dart';
  String get tutorialFile => '$pagePath.md';

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
  };
}

/// Compares two `major.minor.patch` version strings.
///
/// Numeric, not textual: `0.10.0` comes after `0.9.0`. Anything after a `+` or
/// a `-` is ignored, since a build number does not say when a capability
/// arrived.
int compareVersions(String a, String b) {
  List<int> parts(String version) => <int>[
    for (final String part in version.split(RegExp('[+-]')).first.split('.'))
      int.tryParse(part) ?? 0,
  ];
  final List<int> x = parts(a);
  final List<int> y = parts(b);
  for (var i = 0; i < 3; i++) {
    final int left = i < x.length ? x[i] : 0;
    final int right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}
