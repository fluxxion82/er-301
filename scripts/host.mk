# One coherent host toolchain lane for the emulator and host-built mods (Linux, macOS).
#
# The emulator executable and the host mods exchange C++ objects, so they must be
# built by the same compiler against the same C++ standard library. This file sets
# the C compiler, C++ compiler, link driver, archiver and mod link flags together,
# from one GCC installation. It is included by scripts/linux.mk and scripts/darwin.mk,
# so the firmware tree (scripts/env.mk) and third-party mods that include
# scripts/tutorial.mk get the same lane.
#
# Overridable on the command line or in the environment:
#   HOST_GCC_VERSION  Major version of the GCC to use. Default: the newest gcc-N on
#                     PATH that has a matching g++-N and gcc-ar-N (Homebrew installs
#                     gcc-16 and so on). On Linux, plain gcc/g++ when there is none.
#   HOST_MARCH        Extra tuning flags, for example -march=native. Default: none,
#                     so the binaries run on any machine of the same architecture.
#   SWIG              SWIG executable. Default: swig. Must be older than 4.5 (below).
#
# Provides:
#   CC CPP LD AR ...     tool names used by scripts/rules.mk and friends
#   HOST_TOOLCHAIN       lane name used in the build directory, for example gcc16
#   HOST_SIMD_FLAGS      instruction-set baseline the code needs (SSE4 on x86)
#   HOST_EXE_LFLAGS      link flags for the emulator executable
#   HOST_MOD_LFLAGS      link flags for host mods (loadable modules)
#   host_missing_pkgs    $(call host_missing_pkgs,pkgs): the pkg-config packages not found
#   host_require_pkgs    $(call host_require_pkgs,pkgs): stop with a clear error if any is missing
#   host_pkg_cflags      $(call host_pkg_cflags,pkgs)
#   host_pkg_libs        $(call host_pkg_libs,pkgs)

host_os := $(shell uname -s)
host_machine := $(shell uname -m)

# Newest gcc-N on PATH with matching g++-N and gcc-ar-N.
ifndef HOST_GCC_VERSION
HOST_GCC_VERSION := $(shell IFS=:; for d in $$PATH; do ls "$$d" 2>/dev/null; done \
  | sed -n 's/^gcc-\([0-9][0-9]*\)$$/\1/p' | sort -un \
  | while read v; do command -v g++-$$v >/dev/null && command -v gcc-ar-$$v >/dev/null && echo $$v; done \
  | tail -n 1)
endif

ifneq ($(HOST_GCC_VERSION),)
  host_gcc_suffix := -$(HOST_GCC_VERSION)
else ifeq ($(host_os),Linux)
  # No versioned GCC on PATH: use the distribution's default gcc.
  host_gcc_suffix :=
  HOST_GCC_VERSION := $(shell gcc -dumpversion 2>/dev/null | cut -d. -f1)
else
  $(error No GCC found: expected gcc-N, g++-N and gcc-ar-N on PATH (macOS: brew install gcc). \
    Set HOST_GCC_VERSION=N to choose one explicitly)
endif

host_gcc := gcc$(host_gcc_suffix)
host_gxx := g++$(host_gcc_suffix)

# On macOS plain gcc is Apple Clang; make sure the lane really is GCC.
ifeq ($(shell $(host_gcc) -v 2>&1 | grep -c '^gcc version'),0)
  $(error '$(host_gcc)' is missing or is not GCC. Install GCC (macOS: brew install gcc) \
    or set HOST_GCC_VERSION=N)
endif

HOST_TOOLCHAIN := gcc$(HOST_GCC_VERSION)

CC := $(host_gcc) -fdiagnostics-color -fmax-errors=5
CPP := $(host_gxx) -fdiagnostics-color -fmax-errors=5
LD := $(host_gcc) -fdiagnostics-color
AR := gcc-ar$(host_gcc_suffix)
OBJCOPY := objcopy
OBJDUMP := objdump
ADDR2LINE := addr2line
SIZE := size
STRIP := strip
READELF := readelf
NM := nm
SWIG ?= swig
PYTHON := python3
ZIP := zip

# SWIG 4.5 removed -no-old-metatable-bindings (and now always generates the old
# bindings), so it cannot reproduce the firmware's Lua bindings. Use SWIG 4.0-4.4,
# or the firmware image's SWIG through docker/swig.sh.
ifeq ($(filter clean %-clean,$(MAKECMDGOALS)),)
host_swig_version := $(shell $(SWIG) -version 2>/dev/null | sed -n 's/^SWIG Version \([0-9.]*\).*/\1/p')
ifeq ($(host_swig_version),)
  $(error SWIG not found ('$(SWIG)'). macOS: use SWIG=docker/swig.sh (see that file). \
    Ubuntu: sudo apt install swig)
endif
ifneq ($(filter 4.5% 4.6% 4.7% 4.8% 4.9% 5.%,$(host_swig_version)),)
  $(error SWIG $(host_swig_version) ('$(SWIG)') no longer accepts -no-old-metatable-bindings. \
    Use SWIG 4.0-4.4, or pass SWIG=docker/swig.sh to use the firmware image's SWIG 4.0.2)
endif
endif

# Instruction-set baseline. The x86 emulator maps NEON onto SSE through
# emu/hal/neon2sse.h, which needs SSE4. On arm64/aarch64 NEON is always present.
ifneq ($(filter x86_64 amd64 i386 i686,$(host_machine)),)
  HOST_SIMD_FLAGS := -msse4
else
  HOST_SIMD_FLAGS :=
endif

# Tuning is opt-in.
HOST_MARCH ?=

# Executable exports its symbols so that mods can resolve them at load time.
HOST_EXE_LFLAGS := -rdynamic

ifeq ($(host_os),Darwin)
  # A loadable Mach-O bundle; undefined symbols resolve against the emulator at dlopen.
  HOST_MOD_LFLAGS := -bundle -undefined dynamic_lookup
else
  HOST_MOD_LFLAGS := -shared
endif

# Host libraries through pkg-config. Conditions are $(strip)ped because GNU Make 3.81
# (the make that ships with macOS) treats a blank condition in $(if) as true.
HOST_PKG_CONFIG ?= pkg-config
host_missing_pkgs = $(strip $(foreach p,$1,$(if $(shell $(HOST_PKG_CONFIG) --exists $p 2>/dev/null && echo yes),,$p)))
host_require_pkgs = $(if $(strip $(shell command -v $(HOST_PKG_CONFIG))),,$(error pkg-config not found. \
  macOS: brew install pkgconf. Ubuntu: sudo apt install pkg-config))$(if $(call host_missing_pkgs,$1),$(error \
  Missing host libraries (pkg-config): $(call host_missing_pkgs,$1). \
  macOS: brew install sdl2 sdl2_ttf fftw. \
  Ubuntu: sudo apt install libsdl2-dev libsdl2-ttf-dev libfftw3-dev))
# --cflags points inside each package's include directory (for example include/SDL2);
# the sources also include <SDL2/...>, so add the package's include directory itself.
host_pkg_cflags = $(shell $(HOST_PKG_CONFIG) --cflags $1) \
  $(foreach p,$1,-I$(shell $(HOST_PKG_CONFIG) --variable=includedir $p))
host_pkg_libs = $(shell $(HOST_PKG_CONFIG) --libs $1)
