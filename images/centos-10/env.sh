# Enable customize for package installation and service enablement
# customize operation REQUIRED to install packages and enable services
VIRT_SYSPREP_OPERATIONS=net-hostname,net-hwaddr,machine-id,dhcp-server-state,dhcp-client-state,yum-uuid,udev-persistent-net,tmp-files,smolt-uuid,rpm-db,package-manager-cache,customize
_BUILD_DATE=latest
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
BASE_URL=https://cloud.centos.org/centos/10-stream/"${_ARCH}"/images
DOWNLOAD_FILE=CentOS-Stream-GenericCloud-10-latest."${_ARCH}".qcow2
AMD64_SHA256SUM=e35758416cdfa49fab5b1d58e2fbfc16ee139fa2765ce9fefdda8eacf7d5eea4
ARM64_SHA256SUM=cb37826bf79c99ef435da2f3e6d044da884018c24c6c3f8091b566314363e88d
