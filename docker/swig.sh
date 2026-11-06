#!/bin/sh
# Run the SWIG from the firmware toolchain image (docker/Dockerfile.am335x) on the host.
#
#   make emu SWIG=docker/swig.sh
#
# SWIG 4.5 removed -no-old-metatable-bindings, which the firmware's Lua bindings are
# generated with, and Homebrew ships only 4.5. Using the container's SWIG also means
# the emulator, the host mods and the firmware are wrapped by the same SWIG.
#
# This repository (the SDK) and the current directory are mounted at their own paths
# inside the container, so the paths make passes (sources, -I, -o, -MF) work unchanged,
# including a third-party mod outside the tree that points SDKPATH here. Paths outside
# both are not visible to SWIG.
set -eu

image=${ER301_TOOLCHAIN_IMAGE:-er301-am335x-toolchain:4.01.00.06}
if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "docker/swig.sh: image $image not found; build it with docker/am335x.sh true" >&2
  exit 1
fi

sdk=$(cd "$(dirname "$0")/.." && pwd -P)
here=$(pwd -P)
outside=
case $here/ in
  "$sdk"/*) ;;
  *) outside=yes ;;
esac

exec docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  -v "$sdk":"$sdk" ${outside:+-v "$here":"$here"} -w "$here" \
  --entrypoint swig "$image" "$@"
