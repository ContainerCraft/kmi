# Talos Linux 1.11 with qemu-guest-agent via Image Factory
# https://factory.talos.dev/
# Schematic ID: ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515

TALOS_VERSION="v1.11.3"
SCHEMATIC_ID="ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

# Image Factory URLs for metal platform (qcow2 format)
AMD64_BASE_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}"
ARM64_BASE_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}"

AMD64_DOWNLOAD_FILE="metal-amd64.qcow2"
ARM64_DOWNLOAD_FILE="metal-arm64.qcow2"

# No checksums provided by Image Factory API (skipped during build)
# Checksums can be verified manually if needed

# Talos is immutable - skip customization, sparsify, and virt-sysprep
CUSTOMIZE=false
SPARSIFY=false