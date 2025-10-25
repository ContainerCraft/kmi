# Kali Linux Configuration
# Debian-based penetration testing distribution
# https://www.kali.org/

__VERSION="2025.3"
# Preserve kali user account - only clean logs and temp files
# user-account operation removed to keep default kali:kali credentials
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files
AMD64_BASE_URL=https://mirror.fcix.net/kali-images/current/
AMD64_DOWNLOAD_FILE=kali-linux-${__VERSION}-qemu-amd64.7z
AMD64_SHA256SUM=f7d4ffe5cad558c406e1e8f13160b0a8d60283c2eff00c7d7ac91794219916b0

# Kali Linux only provides amd64 images
# The QEMU image is distributed as a 7z archive containing a qcow2 disk
# Documentation: https://www.kali.org/docs/virtualization/install-qemu-guest-vm/
