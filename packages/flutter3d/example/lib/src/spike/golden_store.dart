/// Where a golden run reads its reference and writes its verdict.
///
/// On a desktop build that is the filesystem and a process exit code, which is
/// what `tool/golden.sh` reads. In a browser there is neither: no file to open
/// and no code to return. The references are fetched over HTTP from the same
/// server that served the page, and the verdict goes to the console.
///
/// Conditional for the same reason as the backend: `dart:io` on the web is a
/// stub that throws on first use, so an unguarded `File` is not a fallback that
/// degrades, it is a grey screen at startup.
library;

export 'golden_store_io.dart'
    if (dart.library.js_interop) 'golden_store_web.dart';
