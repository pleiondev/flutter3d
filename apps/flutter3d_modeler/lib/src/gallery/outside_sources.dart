/// The four catalogues outside this repository — `gal-04`.
///
/// **One of them is wired against a format that was read, and three are
/// not.** The Khronos sample assets publish a `model-index.json` whose
/// shape is documented and stable, so `khronosSamples` maps it directly.
/// Smithsonian Open Access, Poly Pizza and Sketchfab each need a key and a
/// live request, and no request to any of them has been made from this
/// session — so their adapters below say what they expect and are left out
/// of [defaultOutsideSources] until somebody has watched one answer.
/// Guessing a response shape and shipping it is how a gallery comes to
/// show an empty grid with no error anybody can act on.
///
/// **Licences are per item, never per source.** Poly Pizza and Sketchfab
/// both hold a mixture, and a source-wide "CC-BY" would mark the CC0 models
/// on them as needing a credit they do not — which would cost somebody a
/// credits file they never owed. Every adapter reads the licence of the
/// item it is building, and an item whose licence it cannot read is one it
/// does not build.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart' show RecipeCategory;

import 'gallery_item.dart';
import 'remote_source.dart';

/// Where the Khronos sample models' own index lives.
const String kKhronosIndex =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
    'main/Models/model-index.json';

/// Where a model named in that index is fetched from.
String khronosModelUrl(String name, String file) =>
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
    'main/Models/$name/glTF-Binary/$file';

/// The glTF sample assets, which are what every decoder in this repository
/// is already tested against.
///
/// **Not every one of them is CC0**, and the index says which: the licence
/// each model carries is read per model and an entry that does not name one
/// is skipped rather than assumed.
RemoteSource khronosSamples({
  required Fetch fetch,
  GalleryCache cache = const NoCache(),
}) => RemoteSource(
  id: 'khronos',
  name: 'glTF sample assets',
  url: kKhronosIndex,
  fetch: fetch,
  cache: cache,
  parse: parseKhronosIndex,
);

/// `model-index.json` as items.
///
/// The index is a list of objects, each with a `name`, a `variants` map
/// from variant name to file name, and a `legal` list whose entries carry
/// `license`, `licenseUrl` and `artist`. Everything this needs is in that;
/// an entry missing any of it is an entry this cannot credit correctly, and
/// is left out.
List<GalleryItem> parseKhronosIndex(Object? body, RemoteSource source) {
  if (body is! List<Object?>) {
    throw const FormatException('the Khronos index is not a list');
  }
  final items = <GalleryItem>[];
  for (final Object? entry in body) {
    if (entry is! Map<String, Object?>) continue;
    final Object? name = entry['name'];
    final Object? variants = entry['variants'];
    final Object? legal = entry['legal'];
    if (name is! String || variants is! Map<String, Object?>) continue;
    final Object? binary = variants['glTF-Binary'];
    if (binary is! String) continue;

    final ({String? artist, GalleryLicence? licence}) terms = _khronosTerms(
      legal,
    );
    final GalleryLicence? licence = terms.licence;
    if (licence == null) continue;
    if (licence.requiresAttribution &&
        (terms.artist == null || terms.artist!.isEmpty)) {
      continue;
    }

    items.add(
      remoteItem(
        source: source,
        id: name,
        name: name,
        about:
            'A glTF sample asset — what this repository\'s own decoders '
            'are tested against.',
        category: categoryFor(name),
        licence: licence,
        author: licence.requiresAttribution ? terms.artist : null,
        downloadUrl: khronosModelUrl(name, binary),
      ),
    );
  }
  return items;
}

/// The first legal entry that names a licence this build knows.
({GalleryLicence? licence, String? artist}) _khronosTerms(Object? legal) {
  if (legal is! List<Object?>) return (licence: null, artist: null);
  for (final Object? entry in legal) {
    if (entry is! Map<String, Object?>) continue;
    final Object? said = entry['license'];
    if (said is! String) continue;
    final GalleryLicence? licence = licenceNamed(said);
    if (licence == null) continue;
    final Object? artist = entry['artist'];
    return (licence: licence, artist: artist is String ? artist : null);
  }
  return (licence: null, artist: null);
}

/// What a catalogue's own licence string means here, or null for one this
/// build does not know.
///
/// **Null rather than a guess.** An unknown licence is the one case where
/// being wrong costs somebody else: marking a restricted model as free is
/// how an export ships without a credit it owed. The item is skipped, and
/// adding a licence here is a deliberate line.
GalleryLicence? licenceNamed(String said) {
  final String word = said.toUpperCase().replaceAll(' ', '');
  if (word.contains('CC0') || word.contains('PUBLICDOMAIN')) {
    return GalleryLicence.cc0;
  }
  if (word.contains('CC-BY-NC') || word.contains('CCBY-NC')) {
    return GalleryLicence.ccByNc4;
  }
  if (word.contains('CC-BY') || word.contains('CCBY')) {
    return GalleryLicence.ccBy4;
  }
  return null;
}

/// The sources the gallery opens with.
///
/// **The built-in recipes and Khronos, and nothing that needs a key.** A
/// source that asks for a key it has not been given would be a row saying
/// "could not be reached" on every launch, which teaches people to ignore
/// that row — and it is the row that has to mean something the day a
/// catalogue really is down.
List<GallerySource> defaultOutsideSources({
  required Fetch fetch,
  GalleryCache cache = const NoCache(),
}) => <GallerySource>[khronosSamples(fetch: fetch, cache: cache)];

/// What a Smithsonian, Poly Pizza or Sketchfab adapter will need from
/// whoever wires it up.
///
/// **Written down rather than half-built.** Each of these needs an API key
/// and a live response nobody has read yet in this repository; the shape of
/// their JSON is not something to guess at, because a guess produces an
/// empty grid and no error a person can act on. When somebody has a key and
/// one real response, the adapter is `parseKhronosIndex`'s own size.
const Map<String, String> outsideSourcesNotWiredYet = <String, String>{
  'smithsonian':
      'Open Access, CC0 throughout. Needs an api.data.gov key and one real '
      'search response to map: the 3D media are under content.descriptiveNon'
      'Repeating.online_media, and the licence is stated per object.',
  'poly-pizza':
      'A mixture of CC0 and CC-BY. Needs a key, and the licence must be read '
      'per model rather than per source — a source-wide licence would mark '
      'its CC0 models as owing a credit they do not.',
  'sketchfab':
      'Mostly CC-BY, some CC0. Needs an OAuth token for downloads; the '
      'search response carries `license` and `user.displayName`, both of '
      'which an item cannot be built without.',
};

/// The one category mapping these catalogues need beyond [categoryFor] —
/// kept here so a source's own parse stays a mapping and nothing else.
RecipeCategory categoryForOutside(String said) => categoryFor(said);
