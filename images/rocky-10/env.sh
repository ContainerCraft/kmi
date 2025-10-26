# Rocky Linux 10 requires x86-64-v3 CPU features, which the libguestfs appliance does not support
# Package installation and service enablement must be done via cloud-init userdata at VM runtime
# customize operation disabled - use cloud-init for package installation
VIRT_SYSPREP_OPERATIONS=net-hostname,net-hwaddr,machine-id,dhcp-server-state,dhcp-client-state,yum-uuid,udev-persistent-net,tmp-files,smolt-uuid,rpm-db,package-manager-cache
AMD64_BASE_URL=https://download.rockylinux.org/pub/rocky/10/images/x86_64/
AMD64_DOWNLOAD_FILE=Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
AMD64_SHA256SUM=20e771c654724e002c32fb92a05fdfdd7ac878c192f50e2fc21f53e8f098b8f9
ARM64_BASE_URL=https://download.rockylinux.org/pub/rocky/10/images/aarch64/
ARM64_DOWNLOAD_FILE=Rocky-10-GenericCloud-Base.latest.aarch64.qcow2
ARM64_SHA256SUM=326264421955473a3576feff35076b7a7ef4bf2a14b5f6d238b7ec65c0426fbc
