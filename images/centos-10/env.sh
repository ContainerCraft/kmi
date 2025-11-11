# CentOS Stream 10 requires x86-64-v3 CPU features, which the libguestfs appliance does not support
# Package installation and service enablement must be done via cloud-init userdata at VM runtime
# customize operation disabled - use cloud-init for package installation
VIRT_SYSPREP_OPERATIONS=net-hostname,net-hwaddr,machine-id,dhcp-server-state,dhcp-client-state,yum-uuid,udev-persistent-net,tmp-files,smolt-uuid,rpm-db,package-manager-cache
# Skip tests that require cloud-init/qemu-guest-agent/SSH (not installed due to x86-64-v3 incompatibility)
SKIP="qemu-guest-agent|ssh"
_BUILD_DATE=20250106.0
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
BASE_URL=https://cloud.centos.org/centos/10-stream/"${_ARCH}"/images
DOWNLOAD_FILE=CentOS-Stream-GenericCloud-10-latest."${_ARCH}".qcow2
AMD64_SHA256SUM=770174fda7d5318f8e07a32f6d62b2bdfaf570de8575ffec9fe282bd945e9e82
ARM64_SHA256SUM=037f216016bd704651e6390d751e22d011598f968b111c1ab420f6f9bd832bef
