#!/bin/sh
# Run a command in the pinned AM335x firmware toolchain container.
#
#   docker/am335x.sh                  # make firmware
#   docker/am335x.sh make doctor      # check the installed toolchain
#   docker/am335x.sh make -j8 core    # any other command
#
# The image is built from docker/Dockerfile.am335x on first use. The repository is
# mounted at the fixed path /src/er-301 so paths seen by the compiler do not depend
# on where the checkout lives. Files are written as the calling user.
#
# Environment:
#   ER301_TOOLCHAIN_IMAGE  image tag (default er301-am335x-toolchain:4.01.00.06)
#   ER301_REBUILD_IMAGE=1  rebuild the image even if it exists
set -eu

image=${ER301_TOOLCHAIN_IMAGE:-er301-am335x-toolchain:4.01.00.06}
repo=$(cd "$(dirname "$0")/.." && pwd)

if [ "${ER301_REBUILD_IMAGE:-0}" = 1 ] || ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build --platform linux/amd64 -f "$repo/docker/Dockerfile.am335x" -t "$image" "$repo/docker"
fi

[ $# -gt 0 ] || set -- make firmware

tty_flag=
[ -t 0 ] && [ -t 1 ] && tty_flag=-t

exec docker run --rm -i $tty_flag --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  -v "$repo":/src/er-301 -w /src/er-301 \
  "$image" "$@"
