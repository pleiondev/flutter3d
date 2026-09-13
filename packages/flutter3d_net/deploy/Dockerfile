# net-02's relay, self-hosted per §3 of doc/tooling-plan.md — one process,
# no database, no state that survives a restart.
#
#     docker build -f packages/flutter3d_net/deploy/Dockerfile -t flutter3d-net-relay .
#     docker run -p 8790:8790 flutter3d-net-relay
#
# Built from the repository root rather than from this directory, because
# `flutter3d_net` resolves `flutter3d_sim` by a relative path inside the
# workspace and the build needs both trees present to run `dart pub get`.

FROM dart:stable AS build
WORKDIR /workspace
COPY pubspec.yaml pubspec.lock ./
COPY packages/flutter3d_sim packages/flutter3d_sim
COPY packages/flutter3d_physics packages/flutter3d_physics
COPY packages/flutter3d_net packages/flutter3d_net
# Every other workspace member is unreached by `flutter3d_net`'s own
# dependency graph and left out on purpose — a relay's image should not
# carry the renderer or the four genres to build.
RUN cd packages/flutter3d_net && dart pub get --offline || dart pub get

EXPOSE 8790
WORKDIR /workspace/packages/flutter3d_net
ENTRYPOINT ["dart", "run", "bin/relay.dart", "8790"]
