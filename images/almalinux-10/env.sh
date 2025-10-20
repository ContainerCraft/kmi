VIRT_SYSPREP_OPERATIONS=net-hostname,net-hwaddr,machine-id,dhcp-server-state,dhcp-client-state,yum-uuid,udev-persistent-net,tmp-files,smolt-uuid,rpm-db,package-manager-cache
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64_v2/;s/arm64/aarch64/')
BASE_URL=https://repo.almalinux.org/almalinux/10/cloud/"${_ARCH}"/images/
DOWNLOAD_FILE=AlmaLinux-10-GenericCloud-latest."${_ARCH}".qcow2
AMD64_SHA256SUM=1d9688e346adb1deaacafc772f8623b3b10d8adfc5c3a421cee28374361d7682
ARM64_SHA256SUM=34f255fab5d82f5470b173016cf7265282f09fc36a0c50fde72c9a7166c450ea