# Kali Linux Configuration
# Debian-based penetration testing distribution
# https://www.kali.org/

__VERSION="2025.3"
# Remove ALL default user accounts for security (cloud-init will create users)
# This removes the default kali:kali account to prevent security exposure
# Additional operations: machine-id (for unique IDs), ssh-hostkeys (regenerate on first boot),
# net-hostname/net-hwaddr (remove hardcoded network config), dhcp states, package cache
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,user-account,machine-id,ssh-hostkeys,ssh-userdir,net-hostname,net-hwaddr,dhcp-client-state,dhcp-server-state,package-manager-cache,utmp,customize
# Kali image already has 110GB virtual size - no resize needed
RESIZE_DISK=false
# Disable sparsify for faster build iteration during testing
SPARSIFY=false
AMD64_BASE_URL=https://mirror.fcix.net/kali-images/current/
AMD64_DOWNLOAD_FILE=kali-linux-${__VERSION}-qemu-amd64.7z
AMD64_SHA256SUM=f7d4ffe5cad558c406e1e8f13160b0a8d60283c2eff00c7d7ac91794219916b0

# Kali Linux only provides amd64 images
# The QEMU image is distributed as a 7z archive containing a qcow2 disk
# Documentation: https://www.kali.org/docs/virtualization/install-qemu-guest-vm/
