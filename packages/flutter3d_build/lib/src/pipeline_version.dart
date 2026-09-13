/// `ap-05`'s own version stamp — bumped by hand whenever this package's
/// conversion or caching logic changes in a way that should force every
/// cached asset to reconvert, even though its source bytes did not change.
///
/// The same hand-maintained pattern `kF3dVersion` already uses in
/// `flutter3d_formats` for the container format itself, applied here to the
/// pipeline that produces it — two different questions ("can this build
/// read the file" and "did the tool that made it change since"), so two
/// different stamps rather than one doing both jobs.
const int kAssetPipelineVersion = 1;
