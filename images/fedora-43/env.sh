# VIRT_SYSPREP_OPERATIONS=user-account,logfiles,customize,bash-history,machine-id,yum-uuid,tmp-files,smolt-uuid,package-manager-cache
VIRT_SYSPREP_OPERATIONS=user-account,logfiles,bash-history
_ARCH=$(echo ${ARCH} | sed 's/amd64/x86_64/;s/arm64/aarch64/')
BASE_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/"${_ARCH}"/images
DOWNLOAD_FILE=Fedora-Cloud-Base-Generic-43-1.1."${_ARCH}".qcow2
AMD64_SHA256SUM=846574c8a97cd2d8dc1f231062d73107cc85cbbbda56335e264a46e3a6c8ab2f
ARM64_SHA256SUM=66031aea9ec61e6d0d5bba12b9454e80ca94e8a79c913d37ded4c60311705b8b
SKIP="ssh"
