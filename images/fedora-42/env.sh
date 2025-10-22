# VIRT_SYSPREP_OPERATIONS=user-account,logfiles,customize,bash-history,machine-id,yum-uuid,tmp-files,smolt-uuid,package-manager-cache
VIRT_SYSPREP_OPERATIONS=user-account,logfiles,bash-history
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
BASE_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/42/Cloud/"${_ARCH}"/images
DOWNLOAD_FILE=Fedora-Cloud-Base-Generic-42-1.1."${_ARCH}".qcow2
AMD64_SHA256SUM=e401a4db2e5e04d1967b6729774faa96da629bcf3ba90b67d8d9cce9906bec0f
ARM64_SHA256SUM=e10658419a8d50231037dc781c3155aa94180a8c7a74e5cac2a6b09eaa9342b7
SKIP="ssh"
