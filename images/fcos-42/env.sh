_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
_BUILD_VERSION="42.20250929.3.0"
BASE_URL=https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/"${_BUILD_VERSION}"/"${_ARCH}"
DOWNLOAD_FILE=fedora-coreos-"${_BUILD_VERSION}"-qemu."${_ARCH}".qcow2.xz
AMD64_SHA256SUM=c096458c7b9c813ea32daa836b4840c438eeb6ef55d08f8b75c03cdc241d85b3
ARM64_SHA256SUM=87c1c4e77c1feefdd6cff5e342cc16ce4fb288e0949e7a3c874c3ec25f7ada80
CUSTOMIZE=false
SKIP="qemu-guest-agent|ssh"
