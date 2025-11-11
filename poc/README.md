# KMI Direct KVM Testing POC

## Purpose

Proof of concept for replacing the KubeVirt-in-kind CI testing pipeline with direct KVM/QEMU testing. This eliminates nested virtualization complexity, reduces test time from 15-20 minutes to 3-5 minutes per flavor, and provides more reliable validation.

## Current Problem

The existing `.github/workflows/test.yml` and `tests/run.bats` use:
- kind (Kubernetes in Docker)
- KubeVirt operator with software emulation (`useEmulation=true`)
- Complex multi-layer networking (Docker → kind → K8s Service → VMI)
- Excessive retry logic (120 retries for qemu-guest-agent, 90 for SSH)
- High failure rate due to timing issues and nested virtualization

## POC Approach

Build and test images directly with KVM using cloud-init ISOs:
1. Build qcow2 image using `hack/customize.sh` (just like CircleCI does)
   - Downloads qcow2 from upstream mirror
   - Verifies checksums
   - Customizes with virt-sysprep (packages, services, etc.)
2. Generate cloud-init ISO with test credentials
3. Launch VM with native KVM acceleration + serial console to file
4. Test qemu-guest-agent connectivity
5. Test SSH connectivity
6. Validate cloud-init completion and disk growth

**Key difference from current approach:** We're testing the ACTUAL build output, not the containerized version. This validates the full hack/customize.sh workflow.

## Files

### `run.sh`
Main test script. Usage:
```bash
./run.sh <flavor> <arch>
./run.sh ubuntu-24-04 amd64
```

**What it does:**
1. **Build Phase:** Runs `../hack/customize.sh <flavor> <arch>`
   - Downloads qcow2 from upstream (e.g., cloud-images.ubuntu.com)
   - Verifies SHA256/SHA512 checksums
   - Resizes disk (+30GB for Nix store)
   - Runs virt-sysprep customization (install packages, enable services)
   - Sparsifies image
   - Output: `<flavor>-<arch>.qcow2`
2. **Prep Phase:**
   - Generates cloud-init ISO with SSH key from `id_rsa.pub`
3. **Launch Phase:**
   - Launches QEMU with KVM, 2GB RAM, 2 CPUs
   - Serial console logs to `serial.log`
4. **Test Phase:**
   - Tests qemu-guest-agent (60 retries × 2s)
   - Tests SSH connectivity (30 retries × 2s)
   - Runs cloud-init status check and disk size validation
5. **Cleanup:** Removes qcow2, ISO, socket, PID file

### `meta-data`
Cloud-init instance metadata (instance-id, hostname)

### `user-data`
Cloud-init configuration:
- Creates `test` user with sudo access
- Injects SSH public key from `id_rsa.pub`
- No package updates (use pre-configured images)

### `id_rsa` / `id_rsa.pub`
SSH keypair for test access. Generated automatically.

### `kubevirt-image-build-runner-vm.yaml`
KubeVirt VM definition for self-hosted GitHub Actions runner:
- **Storage:** 256GB (for multiple test images)
- **Memory:** 32GB
- **CPU:** 8 cores × 2 threads (16 vCPUs) with vmx (nested KVM)
- **Network:** Bridge to br0 (MAC: 52:54:00:0b:00:99)
- **Base:** ubuntu-24-04-dev image
- **Packages:** docker, qemu-kvm, libvirt, cloud-image-utils, socat, libguestfs-tools, skopeo, jq, gh, bats

**Why a VM runner:**
- Need nested KVM support for testing VMs inside VMs
- Persistent environment for debugging
- Can install Nix/Mise for Kalilix tooling
- Matches GHA runner environment

## Next Steps

1. **Validate POC:** Test ubuntu-24-04 image end-to-end
2. **Add more tests:** Package manager, services, distribution-specific checks
3. **Handle edge cases:** FCOS (Ignition), Talos (API-only), FreeBSD (different init)
4. **Create GHA workflow:** `.github/workflows/test-kvm.yml`
5. **Replace old pipeline:** Deprecate `test.yml` and `tests/run.bats`

## Success Criteria

- ✅ hack/customize.sh builds ubuntu-24-04 image successfully
- ✅ Boots customized qcow2 with KVM
- ✅ Serial console logs to file for debugging
- ✅ qemu-guest-agent responds within 2 minutes
- ✅ SSH connects within 1 minute
- ✅ cloud-init completes successfully
- ✅ Disk growth verified (>30GB from customize.sh resize)
- ✅ Installed packages present (qemu-guest-agent, openssh-server, etc.)
- ✅ Full workflow completes in <10 minutes

## Design Constraints

- **No kubectl/virtctl:** We're eliminating Kubernetes/KubeVirt from tests
- **No podman:** Use Docker (buildx, standard tooling)
- **No curl-installed binaries:** Use apt packages only
- **No mise/nix in cloud-init:** Already baked into images
- **Simple is better:** 50-line script vs 700-line plan

## Testing Workflow

```bash
# On kmi-runner VM
cd /tmp
git clone https://github.com/ContainerCraft/kmi
cd kmi/poc

# Run POC test
./run.sh ubuntu-24-04 amd64

# Expected output:
# - Download qcow2: ~30-60s (varies by mirror speed)
# - Customize with virt-sysprep: ~2-5 minutes (KVM accelerated)
# - Generate ISO: <1s
# - Boot VM: ~30-60s
# - qemu-guest-agent: ~10-30s
# - SSH ready: ~10-30s
# - Tests complete: ~10s
# Total: ~5-8 minutes (most time is customize.sh)
```

**Serial console log:**
All VM boot output is saved to `serial.log` for debugging. If tests fail, check this file first.

## Architecture Decision

**Why direct KVM over KubeVirt-in-kind?**

| Aspect | KubeVirt-in-kind | Direct KVM |
|--------|------------------|------------|
| Virtualization | TCG emulation | Native KVM |
| Boot time | 5-10 min | 30-60s |
| Test time | 15-20 min | 3-5 min |
| Components | 7 (kind, kubectl, KubeVirt, virtctl, CNI, operator, CRDs) | 2 (qemu-kvm, cloud-utils) |
| Networking | 4 layers | 1 layer |
| Flakiness | High | Low |
| Resource usage | 6-8GB RAM | 2-3GB RAM |
| Debugging | Multi-layer logs | Direct console |

**Bottom line:** We're testing VM disk images, not KubeVirt orchestration. Test what we ship.

## Branch Strategy

This POC work is on branch: `feat/test-validation-promotion-pipeline-redesign`

Once validated, we'll:
1. Update `.circleci/config.yml` to trigger new workflow
2. Create `.github/workflows/test-kvm.yml`
3. Deprecate `.github/workflows/test.yml` → `test-kubevirt-legacy.yml`
4. Remove `tests/run.bats`, `tests/vmi.yaml`, etc.
5. Update documentation

## Notes

- The kmi-runner VM is deployed and running as a self-hosted GitHub Actions runner
- Runner has Lix/Nix installed with Kalilix devops shell available
- All development/testing happens in this runner environment
- POC must prove faster, simpler, more reliable than current approach
