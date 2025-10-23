# VyOS 1.5 Stream Build Configuration
# VyOS uses a custom build system rather than downloadable qcow2 images
# https://docs.vyos.io/en/latest/contributing/build-vyos.html

BUILD_METHOD=vyos-build
VYOS_BRANCH=circinus
VYOS_VERSION=1.5
BUILD_FLAVOR=kmi-qcow2

# VyOS Stream releases are quarterly tech previews for the upcoming LTS
# Rolling builds are also available from the 'current' branch
# Documentation: https://vyos.io/get/

# This image requires building from source using the vyos-build container
# The build process produces a qcow2 image with qemu-guest-agent