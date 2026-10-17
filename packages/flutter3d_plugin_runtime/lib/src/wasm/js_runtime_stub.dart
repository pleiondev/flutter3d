import 'abi.dart';

/// The browser's own WebAssembly, where there is one: off the web there is
/// none, and the interpreter runs every module.
WasmRuntime? browserWasmRuntime() => null;
