#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="$WORKSPACE_DIR/.sonar/cfamily"
EXTRACTED_BUILD_DIR="$ARTIFACT_DIR/build-root"
IMAGE_TAG="${IMAGE_TAG:-cfs-interop-sonar-builder}"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$EXTRACTED_BUILD_DIR"

docker build \
    --target builder \
    -t "$IMAGE_TAG" \
    -f "$SCRIPT_DIR/docker/Dockerfile" \
    "$SCRIPT_DIR"

container_id="$(docker create "$IMAGE_TAG")"
cleanup() {
    docker rm -f "$container_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$EXTRACTED_BUILD_DIR"
docker cp "$container_id:/build/." "$EXTRACTED_BUILD_DIR/"

sudo rm -rf /build
sudo mkdir -p /build
sudo cp -a "$EXTRACTED_BUILD_DIR/." /build/

raw_compile_commands="$EXTRACTED_BUILD_DIR/build/compile_commands.json"
final_compile_commands="$ARTIFACT_DIR/compile_commands.json"

jq \
    --arg workspace "$WORKSPACE_DIR" \
    '
    def normalize_file:
        if .file | startswith("/") then
            .file
        else
            .directory + "/" + .file
        end;

    def remap_file($path):
        if $path | endswith("/cfs-bundle/psp/fsw/modules/stcpsock_intf/stcpsock_intf.c") then
            $workspace + "/tests/interop/NASA-cFS/stcpsock_intf/stcpsock_intf.c"
        elif $path | endswith("/src/echo_app/fsw/src/echo_app.c") then
            $workspace + "/tests/interop/NASA-cFS/echo_app/fsw/src/echo_app.c"
        elif $path | endswith("/src/bpnode/fsw/tables/bpnode_adup.c") then
            $workspace + "/tests/interop/NASA-cFS/cfs-config/bpnode_adup.c"
        elif $path | endswith("/interop_defs/sch_lab_table.c") then
            $workspace + "/tests/interop/NASA-cFS/cfs-config/sch_lab_table.c"
        else
            null
        end;

    map(. + {source_file: (normalize_file | remap_file(.))})
    | map(select(.source_file != null))
    | map(
        .file = .source_file
        | .command = (
            (.command // "")
            | gsub("/build/cfs-bundle/psp/fsw/modules/stcpsock_intf/stcpsock_intf.c"; $workspace + "/tests/interop/NASA-cFS/stcpsock_intf/stcpsock_intf.c")
            | gsub("/build/src/echo_app/fsw/src/echo_app.c"; $workspace + "/tests/interop/NASA-cFS/echo_app/fsw/src/echo_app.c")
            | gsub("/build/src/bpnode/fsw/tables/bpnode_adup.c"; $workspace + "/tests/interop/NASA-cFS/cfs-config/bpnode_adup.c")
            | gsub("/build/interop_defs/sch_lab_table.c"; $workspace + "/tests/interop/NASA-cFS/cfs-config/sch_lab_table.c")
          )
        | .arguments = (
            (.arguments // [])
            | map(
                if . == "/build/cfs-bundle/psp/fsw/modules/stcpsock_intf/stcpsock_intf.c" then
                    $workspace + "/tests/interop/NASA-cFS/stcpsock_intf/stcpsock_intf.c"
                elif . == "/build/src/echo_app/fsw/src/echo_app.c" then
                    $workspace + "/tests/interop/NASA-cFS/echo_app/fsw/src/echo_app.c"
                elif . == "/build/src/bpnode/fsw/tables/bpnode_adup.c" then
                    $workspace + "/tests/interop/NASA-cFS/cfs-config/bpnode_adup.c"
                elif . == "/build/interop_defs/sch_lab_table.c" then
                    $workspace + "/tests/interop/NASA-cFS/cfs-config/sch_lab_table.c"
                else
                    .
                end
            )
          )
        | del(.source_file)
    )
    ' \
    "$raw_compile_commands" > "$final_compile_commands"

jq -e 'length > 0' "$final_compile_commands" >/dev/null
