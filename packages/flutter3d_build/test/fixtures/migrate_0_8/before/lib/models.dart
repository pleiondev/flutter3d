/// The project's own `textureBytes`. 1.0's facade exports one too; a library
/// importing both is ambiguous, and the migration hides the facade's.
String textureBytes(String name) => 'bytes:$name';
