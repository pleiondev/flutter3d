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
///
/// **Version 2** adds `atomic` buffers of `i32` or `u32` and the calls that
/// read and write them, `atomicLoad`, `atomicStore`, `atomicExchange` and
/// `atomicAdd`: what a list built by many invocations at once — a grid of
/// neighbours — needs. A source that uses them opens with `kernel 2`.
const int kernelLanguageVersion = 2;

/// The version a source without a `kernel <N>` line is.
const int kernelLanguageFirstVersion = 1;
