/// `ap-05`'s own version stamp — bumped by hand whenever this package's
/// conversion or caching logic changes in a way that should force every
/// cached asset to reconvert, even though its source bytes did not change.
///
/// The same hand-maintained pattern `kF3dVersion` already uses in
/// `flutter3d_formats` for the container format itself, applied here to the
/// pipeline that produces it — two different questions ("can this build
/// read the file" and "did the tool that made it change since"), so two
/// different stamps rather than one doing both jobs.
///
/// 2: `C5` — a manifest rule's `lods:` reaches the converter, so a model
/// cached before it may be missing the levels its rule now asks for, or the
/// impostor (`C4`) its rule's `impostor:` does.
///
/// 3: `P8` — a material's bundle carries its source in a section of its own,
/// which the software backend compiles and a runtime builds the material's
/// lighting model from; a bundle cached before it has neither.
const int kAssetPipelineVersion = 3;
