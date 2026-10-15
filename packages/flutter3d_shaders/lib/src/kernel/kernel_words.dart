/// The kernel language's words, each with the version it arrived in — 1.0.
///
/// **A word belongs to a version, not to the language.** A name the parser
/// reads as a word of its own — a declaration, a statement, a type, a
/// builtin, a binding's access or format — is taken from a source's
/// bindings and locals only in a source of that version or later. A later
/// version's words are free names in an older source, so a version that
/// adds `barrier` or `shared` never refuses a kernel that was read before
/// it. A source of an older version neither calls such a word nor
/// dispatches on it: it is a name like any other there.
///
/// `tool/structure` holds the parser to this file: every word it dispatches
/// on is here or in [kernelOtherLanguageWords], every version is one this
/// build reads, and [kernelWordsReservedEarly] holds version 2's words and
/// nothing else.
library;

/// The version each word of the kernel language arrived in, by name.
///
/// A word a later version adds is written here with that version, and a
/// source of an older one keeps the name for a binding or a local.
const Map<String, int> kernelWordVersions = <String, int>{
  // The blocks and declarations.
  'compute': 1,
  'workgroup': 1,
  'kernel': 1,
  // Binding words: the kinds, a buffer's access, a texture's format.
  'buffer': 1,
  'texture': 1,
  'image': 1,
  'read': 1,
  'read_write': 1,
  'rgba8': 1,
  // Statements.
  'let': 1,
  'var': 1,
  'if': 1,
  'else': 1,
  'for': 1,
  'in': 1,
  'break': 1,
  'continue': 1,
  'return': 1,
  'store': 1,
  // Values and types.
  'true': 1,
  'false': 1,
  'id': 1,
  'f32': 1,
  'i32': 1,
  'u32': 1,
  'bool': 1,
  'vec2': 1,
  'vec3': 1,
  'vec4': 1,
  // Builtins.
  'load': 1,
  'len': 1,
  'width': 1,
  'height': 1,
  'min': 1,
  'max': 1,
  'clamp': 1,
  'abs': 1,
  'floor': 1,
  'ceil': 1,
  'round': 1,
  'trunc': 1,
  'sqrt': 1,
  'sin': 1,
  'cos': 1,
  'pow': 1,
  'select': 1,
  // Version 2: atomic buffers and the calls that read and write them.
  'atomic': 2,
  'atomicLoad': 2,
  'atomicStore': 2,
  'atomicExchange': 2,
  'atomicAdd': 2,
};

/// Words taken from a source older than the version they arrived in:
/// version 2's, and only those.
///
/// **Kept as they were, on purpose.** Version 1 was read with a single
/// list of words, which already held these, so no version 1 source ever
/// named a binding or a local after them. Freeing them would let nothing
/// parse that parsed before, and would make a name legal in version 1 that
/// is refused in version 2. A word of version 3 or later never joins this
/// set: it is taken only in a source of its own version.
const Set<String> kernelWordsReservedEarly = <String>{
  'atomic',
  'atomicLoad',
  'atomicStore',
  'atomicExchange',
  'atomicAdd',
};

/// Words the kernel parser recognises only to name the other language: a
/// `.f3dmat` file's version line and blocks, and the material language's
/// `compute` form. None of them is taken from a kernel's names.
const Set<String> kernelOtherLanguageWords = <String>{
  'f3dmat',
  'material',
  'fullscreen',
  'uniform',
  'param',
};

/// Whether [name] is a word in a source of kernel language [version]: one
/// it calls and dispatches on.
bool isKernelWord(
  String name,
  int version, {
  Map<String, int> words = kernelWordVersions,
}) => switch (words[name]) {
  final since? => since <= version,
  null => false,
};

/// Whether [name] is taken from a binding or a local in a source of kernel
/// language [version]: a word of that version, or one of
/// [kernelWordsReservedEarly].
bool isKernelReservedName(
  String name,
  int version, {
  Map<String, int> words = kernelWordVersions,
}) =>
    isKernelWord(name, version, words: words) ||
    kernelWordsReservedEarly.contains(name);
