/// `mcp-13n`'s `--mcp-port`: the same live [ModelHistory] a person is
/// editing in this window, reached over a local HTTP socket beside it — the
/// same conditional-export split `close_beforeunload.dart` and
/// `project_files.dart` already use, and for the same reason:
/// `flutter3d_model_mcp` reaches `dart:io`'s `HttpServer`, which has no web
/// counterpart to compile against.
library;

export 'mcp_bootstrap_io.dart'
    if (dart.library.js_interop) 'mcp_bootstrap_web.dart';
