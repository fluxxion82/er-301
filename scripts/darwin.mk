# Build tools for macOS: the host GCC lane is defined in scripts/host.mk.
include $(dir $(lastword $(MAKEFILE_LIST)))host.mk
