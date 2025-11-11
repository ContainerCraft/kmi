VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,package-manager-cache
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
__LEAP_VERSION="16.0"
BASE_URL=https://download.opensuse.org/distribution/leap/"${__LEAP_VERSION}"/appliances/
AMD64_DOWNLOAD_FILE=Leap-"${__LEAP_VERSION}"-Minimal-VM.x86_64-kvm-and-xen.qcow2
ARM64_DOWNLOAD_FILE=Leap-"${__LEAP_VERSION}"-Minimal-VM.aarch64-kvm.qcow2
AMD64_SHA256SUM=478dff9b2d5ec93abf262aab3670b9db0fa14ffdd94864821cfbfd3096e37621
AMD64_SHA256SUM=478dff9b2d5ec93abf262aab3670b9db0fa14ffdd94864821cfbfd3096e37621
SKIP=ssh
# Disable sparsify - upstream image already sparsified, btrfs subvolume processing takes 3+ hours
SPARSIFY=false
