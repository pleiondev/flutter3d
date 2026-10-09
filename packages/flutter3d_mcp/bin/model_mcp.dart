/// A model editor an agent can drive, speaking MCP over stdin and stdout.
///
///     dart run flutter3d_mcp:model_mcp <project.f3dproj>
///
/// **The project is an argument, and there is no tool to change it.** The
/// project is the state: an agent that could open a second one halfway
/// through would be left holding an undo stack describing a file it is no
/// longer editing. A host that wants two projects open starts two processes.
///
/// **A path that does not exist yet starts a fresh project there** — `Г8`'s
/// decision — so the first call an agent makes can be `addPrimitive` rather
/// than a separate "create" step nothing else in this repository has either.
///
/// Nothing is written to stdout that is not a protocol message — stdout *is*
/// the channel — so the one thing that can go wrong before the protocol
/// starts, a project that exists but will not parse, is written to stderr and
/// the process exits non-zero. Registered as `bin/` rather than as an
/// `executables:` entry, matching every other package in this repository.
library;

import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_mcp/model.dart';

/// **An empty [McpTools]**: this package compiles in no plugins. A project
/// offers its own plugins' tools by starting the server from a `bin/` of its
/// own through [serveModelMcp], with the registry its plugins filled.
void main(List<String> arguments) =>
    serveModelMcp(arguments, projectTools: McpTools());
