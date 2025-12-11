# Kali Linux Configuration
# Debian-based penetration testing distribution
# https://www.kali.org/

__VERSION="2025.4"
# Preserve kali user account - only clean logs and temp files
# user-account operation removed to keep default kali:kali credentials
# customize operation REQUIRED to install packages and enable services
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
AMD64_BASE_URL=https://kali.download/base-images/kali-${__VERSION}/
AMD64_DOWNLOAD_FILE=kali-linux-${__VERSION}-qemu-amd64.7z
AMD64_SHA256SUM=e4b958f89d5c26f672a140628315a3a8f733fde9830722ae3d371b5536285d1d

# Kali Linux only provides amd64 images
# The QEMU image is distributed as a 7z archive containing a qcow2 disk
# Documentation: https://www.kali.org/docs/virtualization/install-qemu-guest-vm/

# Reduce disk resize to fit CI runner disk constraints
QCOW2_RESIZE=+10G

# Disable sparsify - CI runner disk too small for Kali image processing
SPARSIFY=false
