# VyOS Rolling Release Build Configuration
# VyOS uses a custom build system rather than downloadable qcow2 images
# https://docs.vyos.io/en/latest/contributing/build-vyos.html

BUILD_METHOD=vyos-build
VYOS_BRANCH=current
VYOS_VERSION=rolling
BUILD_FLAVOR=kmi-qcow2

# VyOS Rolling release contains the latest development code
# Stream and LTS releases require subscription/authentication
# Documentation: https://vyos.io/get/

# This image requires building from source using the vyos-build container
# The build process produces a qcow2 image with qemu-guest-agent