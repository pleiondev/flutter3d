/// The kernel language's version — 1.0.
library;

/// The kernel language version this build reads, and every one below it.
///
/// A source may open with `kernel <N>`; without that line it is version
/// [kernelLanguageFirstVersion]. A source of a later version is refused
/// with a sentence naming both, as a newer file is (`docs/CONTRACTS.md`),
/// rather than read under this build's meaning of its words. The material
/// language's `compute` form is lowered to this language, so it is written
/// in this version too.
const int kernelLanguageVersion = 1;

/// The version a source without a `kernel <N>` line is.
const int kernelLanguageFirstVersion = 1;
