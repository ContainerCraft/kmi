_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
_BUILD_VERSION="43.20251024.3.0"
BASE_URL=https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/"${_BUILD_VERSION}"/"${_ARCH}"
DOWNLOAD_FILE=fedora-coreos-"${_BUILD_VERSION}"-qemu."${_ARCH}".qcow2.xz
AMD64_SHA256SUM=19d0b42d0b2b45e8c336dd18f01d113c0c423782598080890611f79089c285f7
ARM64_SHA256SUM=e2e6ea8fafdbecf3553cc4f4a38b60dec519f6c92a2a6bcb96e1b8d8f6c7e75e
CUSTOMIZE=false
SKIP="qemu-guest-agent|ssh"
