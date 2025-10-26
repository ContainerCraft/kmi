# DNS Resolution Remediation - Implementation Tasks

## Executive Summary

This document captures the complete knowledge transfer, root cause analysis, and implementation plan for re-enabling the `customize` virt-sysprep operation across all KMI (KubeVirt Machine Images) that require package installation and service enablement.

### Problem Statement

Package installation via virt-sysprep was disabled when CircleCI runners were upgraded from Ubuntu 22.04 to Ubuntu 24.04 due to DNS resolution failures. The root cause is a libguestfs incompatibility with Ubuntu 24.04's systemd-resolved DNS configuration.

### Solution Implemented

Downgrade CircleCI runners from Ubuntu 24.04 (ubuntu-2404:2025.09.1) to Ubuntu 22.04 (ubuntu-2204:2025.09.1) to restore libguestfs DNS compatibility.

---

## Table of Contents

1. [Root Cause Analysis](#root-cause-analysis)
2. [Working Solution](#working-solution)
3. [Implementation Tasks](#implementation-tasks)
4. [Image-Specific Implementation Matrix](#image-specific-implementation-matrix)
5. [Validation Checklist](#validation-checklist)
6. [Rollback Plan](#rollback-plan)

---

## Root Cause Analysis

### The libguestfs DNS Resolution Issue

**Technical Details:**

libguestfs daemon code (`daemon/sh.c`) performs the following sequence when running commands in the guest:

```
1. Rename guest's /etc/resolv.conf → /etc/<random-temp-name>
2. Copy appliance's /etc/resolv.conf → guest's /etc/resolv.conf
3. Execute the command
4. Rename temp file back → /etc/resolv.conf
```

**The Problem on Ubuntu 24.04:**

- Ubuntu 24.04 uses systemd-resolved with /etc/resolv.conf as a symlink
- The libguestfs appliance (minimal initrd) doesn't have a valid /etc/resolv.conf
- Step 2 fails: `cp: cannot stat '/etc/resolv.conf': No such file or directory`

**Why Ubuntu 22.04 Works:**

Ubuntu 22.04 has a traditional /etc/resolv.conf file that libguestfs can copy successfully, enabling DNS resolution during package installation.

---

## Working Solution

### Current Status (Debian/Ubuntu/Kali)

All Debian-based images now successfully build with:

1. ✅ Ubuntu 22.04 CircleCI runners
2. ✅ `customize` operation enabled in env.sh
3. ✅ Package installation working (cloud-init, openssh-server, qemu-guest-agent, etc.)
4. ✅ Service enablement working (all cloud-init services, ssh, qemu-guest-agent)

**Key Configuration Files:**

**env.sh:**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**virt.sysprep:**
```bash
# Create resolv.conf for DNS resolution (defensive, not strictly needed on Ubuntu 22.04)
run-command sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

update
install cloud-init,cloud-initramfs-growroot,openssh-server,qemu-guest-agent,python3,tmux,git,vim,btop
run-command systemctl enable qemu-guest-agent
run-command systemctl enable ssh
run-command systemctl enable cloud-init-local.service
run-command systemctl enable cloud-init-network.service
run-command systemctl enable cloud-config.service
run-command systemctl enable cloud-final.service
run-command apt-get autoremove -y && apt-get clean
```

**Note:** The resolv.conf creation via `run-command sh -c` is defensive programming for potential future OS upgrades, though not strictly required on Ubuntu 22.04.

---

## Implementation Tasks

### Phase 1: Review Current Image Status

#### ☐ Task 1.1: Audit all image env.sh files for VIRT_SYSPREP_OPERATIONS

**Purpose:** Identify which images have `customize` disabled and need re-enablement

**Locations to check:**
- `images/*/env.sh`

**Expected patterns:**

**Disabled (needs fix):**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files
```

**Enabled (working):**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**Notes:**
- FreeBSD may use different operations (check `images/freebsd-15/env.sh`)
- Talos/VyOS/OpenWrt may not use virt-sysprep at all (BUILD_METHOD=vyos-build or no customization)

---

#### ☐ Task 1.2: Identify images that don't need customize

**Exempt from this work:**

1. **VyOS Rolling** (`images/vyos-rolling/`)
   - Uses BUILD_METHOD=vyos-build (Docker-based build)
   - No virt-sysprep customization
   - Skip entirely

2. **Talos Linux** (`images/talos-1-11/`)
   - Pre-built immutable OS image
   - Check if virt-sysprep is used at all
   - May only need disk resize/sparsify

3. **Fedora CoreOS** (`images/fcos-42/`)
   - Container-optimized OS
   - Check customization requirements
   - May use ignition instead

4. **OpenWrt** (`images/openwrt-24/`)
   - Embedded router OS
   - Check if packages need installation

5. **FreeBSD** (`images/freebsd-15/`)
   - Different OS family, may have different virt-sysprep requirements
   - Validate separately

**Action:** Document exemptions with reasoning

---

### Phase 2: Re-enable customize Operation

#### ☐ Task 2.1: Update Debian-based distributions

**Target Images:**
- ✅ `images/debian-13/` - COMPLETED
- ✅ `images/ubuntu-24-04/` - COMPLETED
- ✅ `images/kali-linux/` - COMPLETED

**Implementation:**

**env.sh:**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**virt.sysprep:**
```bash
# Create resolv.conf FIRST to enable DNS resolution for package installation
# This is required because libguestfs appliance may not have valid DNS config
run-command sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

update
install cloud-init,cloud-initramfs-growroot,openssh-server,qemu-guest-agent,python3,tmux,git,vim,btop
run-command systemctl enable qemu-guest-agent
run-command systemctl enable ssh
run-command systemctl enable cloud-init-local.service
run-command systemctl enable cloud-init-network.service
run-command systemctl enable cloud-config.service
run-command systemctl enable cloud-final.service
run-command apt-get autoremove -y && apt-get clean
```

---

#### ☐ Task 2.2: Update RPM-based distributions

**Target Images:**
- `images/fedora-42/`
- `images/almalinux-10/`
- `images/centos-10/`
- `images/rocky-10/`

**Implementation:**

**env.sh:**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**virt.sysprep:**
```bash
# Create resolv.conf FIRST to enable DNS resolution for package installation
run-command sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

update
install cloud-init,cloud-utils-growpart,openssh-server,qemu-guest-agent,python3,tmux,git,vim,btop
run-command systemctl enable qemu-guest-agent
run-command systemctl enable sshd
run-command systemctl enable cloud-init-local.service
run-command systemctl enable cloud-init-network.service
run-command systemctl enable cloud-config.service
run-command systemctl enable cloud-final.service
```

**Distribution-Specific Notes:**

- **Fedora:** Uses DNF package manager
- **AlmaLinux/CentOS/Rocky:** Use DNF (RHEL clones)
- **Service name:** `sshd` not `ssh`

---

#### ☐ Task 2.3: Update openSUSE distributions

**Target Images:**
- `images/opensuse-leap-16/`
- `images/opensuse-tumbleweed/`

**Implementation:**

**env.sh:**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**virt.sysprep:**
```bash
# Create resolv.conf FIRST to enable DNS resolution for package installation
run-command sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

update
install cloud-init,openssh,qemu-guest-agent,python3,tmux,git,vim,btop
run-command systemctl enable qemu-guest-agent
run-command systemctl enable sshd
run-command systemctl enable cloud-init-local.service
run-command systemctl enable cloud-init-network.service
run-command systemctl enable cloud-config.service
run-command systemctl enable cloud-final.service
```

**openSUSE-Specific Notes:**

- Uses zypper package manager
- Tumbleweed is rolling release (auto-update checksums in hack/update.sh)
- Leap is stable release

---

#### ☐ Task 2.4: Update Arch Linux

**Target Image:**
- `images/archlinux-latest/`

**Implementation:**

**env.sh:**
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**virt.sysprep:**
```bash
# Create resolv.conf FIRST to enable DNS resolution for package installation
run-command sh -c 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

update
install cloud-init,openssh,qemu-guest-agent,python,tmux,git,vim,btop
run-command systemctl enable qemu-guest-agent
run-command systemctl enable sshd
run-command systemctl enable cloud-init-local.service
run-command systemctl enable cloud-init-network.service
run-command systemctl enable cloud-config.service
run-command systemctl enable cloud-final.service
```

**Arch-Specific Notes:**

- Uses pacman package manager
- Rolling release, may need update.sh support
- Package name: `python` not `python3`

---

### Phase 3: Cloud-init Service Configuration

#### Cloud-init Systemd Services

Based on canonical/cloud-init documentation, the following services exist and should be explicitly enabled:

**Services to Enable:**
1. `cloud-init-local.service` - Local stage (earliest boot, pre-network)
2. `cloud-init-network.service` - Network stage (post v24.3, was `cloud-init.service`)
3. `cloud-config.service` - Config stage
4. `cloud-final.service` - Final stage (late boot, like rc.local)

**Important Notes:**
- These services are auto-enabled when cloud-init package is installed
- Explicit enabling provides fail-fast validation during image build
- `cloud-init.target` is a systemd target, not a service - do not enable explicitly
- Old name `cloud-init.service` was renamed to `cloud-init-network.service` in v24.3+

**Packages:**
- `cloud-init` - Core package (always required)
- `cloud-initramfs-growroot` (Debian/Ubuntu) or `cloud-utils-growpart` (RHEL) - Root filesystem growth (included for compatibility, cloud-init has built-in growpart)
- `openssh-server` (Debian/Ubuntu) or `openssh` (others) - SSH server
- `qemu-guest-agent` - VM guest integration

---

### Phase 4: Testing and Validation

#### ☐ Task 4.1: Local testing with virt-sysprep

**For each modified image, test locally:**

```bash
# Example: Testing Debian 13
export FLAVOR=debian-13
export ARCH=amd64

# Run customization script
./hack/customize.sh

# Expected success indicators:
# 1. virt-sysprep completes without DNS errors
# 2. "Updating packages" appears in logs
# 3. apt-get update/install succeed
# 4. No "Temporary failure resolving" errors
```

**Validation criteria:**
- ✅ No DNS resolution errors
- ✅ Packages install successfully
- ✅ Services are enabled
- ✅ QCOW2 image created successfully

---

#### ☐ Task 4.2: CircleCI build validation

**For each image, monitor CircleCI build:**

1. Push changes to trigger CircleCI workflow
2. Monitor build logs for DNS resolution
3. Verify virt-sysprep customize step succeeds
4. Confirm Docker image is published to DockerHub

**Build log validation:**

```
Expected SUCCESS pattern:
[  XX.X] Updating packages
apt-get update
apt-get install ...
Synchronizing state of ssh.service...
Synchronizing state of cloud-init-local.service...
Synchronizing state of cloud-init-network.service...
Synchronizing state of cloud-config.service...
Synchronizing state of cloud-final.service...

NOT expected FAILURE pattern:
Temporary failure resolving 'http.debian.org'
E: Failed to fetch ...
Failed to enable unit: Unit cloud-init.service does not exist
```

**Action:** Document build URLs and results for each image

---

#### ☐ Task 4.3: KubeVirt VM deployment testing

**For each image, deploy test VM:**

```bash
# Example: Testing Debian 13 VM
cd examples/debian/
./deploy.sh

# Monitor VM startup
kubectl get vm,vmi,dv,pvc
kubectl logs -f virt-launcher-debian-13-xxxxx

# Validation checks:
# 1. VM starts successfully
# 2. Cloud-init runs without errors
# 3. SSH access works with injected key
# 4. qemu-guest-agent is running
```

**Validation criteria per VM:**
- ✅ VM boots and reaches running state
- ✅ Cloud-init completes successfully (check /var/log/cloud-init-output.log)
- ✅ SSH access works with public key authentication
- ✅ qemu-guest-agent is active (verify with `virtctl guestosinfo`)
- ✅ Network connectivity works (DHCP, DNS)

---

#### ☐ Task 4.4: Regression testing for existing working images

**Verify no breakage for:**
- Kali Linux (already working, updated)
- Debian 13 (updated)
- Ubuntu 24.04 (updated)

**Quick validation:**
```bash
# Build and test each flavor
for FLAVOR in kali-linux debian-13 ubuntu-24-04; do
  export FLAVOR ARCH=amd64
  ./hack/customize.sh
  # Check exit code
  if [[ $? -eq 0 ]]; then
    echo "✅ $FLAVOR build succeeded"
  else
    echo "❌ $FLAVOR build failed"
  fi
done
```

---

### Phase 5: Documentation Updates

#### ☐ Task 5.1: Update README.md with customize status

**File:** `README.md`

**Add column or note about customization:**

| Distribution | Version | Status | AMD64 | ARM64 | Container Image | Customization |
|--------------|---------|--------|-------|-------|-----------------|---------------|
| Kali Linux | 2025.3 | Stable | ✅ | ❌ | `containercraft/kali:latest` | ✅ Enabled |
| Debian | 13 | Stable | ✅ | ✅ | `containercraft/debian:13` | ✅ Enabled |
| Ubuntu | 24.04 | Stable | ✅ | ✅ | `containercraft/ubuntu:24-04` | ✅ Enabled |

---

#### ☐ Task 5.2: Document libguestfs DNS issue

**Create:** `docs/libguestfs-dns-resolution.md` or add section to existing docs

**Contents:**
- Root cause explanation
- Ubuntu 22.04 vs 24.04 differences
- Why we use Ubuntu 22.04 runners
- Future mitigation strategies
- Reference to this TASKS document

---

#### ☐ Task 5.3: Update CHANGELOG or release notes

**Document changes:**
- Re-enabled customize operation for all supported distributions
- CircleCI runner version locked to Ubuntu 22.04 for libguestfs compatibility
- Added resolv.conf creation for future-proofing
- Enhanced package installation and service enablement

---

### Phase 6: Future-Proofing and Monitoring

#### ☐ Task 6.1: Monitor libguestfs upstream for Ubuntu 24.04 fix

**Resources to watch:**
- libguestfs mailing list: https://listman.redhat.com/mailman/listinfo/libguestfs
- libguestfs GitLab: https://gitlab.com/libguestfs/libguestfs
- Ubuntu libguestfs package: https://launchpad.net/ubuntu/+source/libguestfs

**Action:** Set up monitoring for releases that fix systemd-resolved compatibility

---

#### ☐ Task 6.2: Test Ubuntu 24.04 compatibility periodically

**Quarterly test:**
1. Create test branch with ubuntu-2404 executors
2. Run build for one distribution (e.g., Debian 13)
3. Check if DNS resolution works
4. Document results

**Migration criteria:**
- ✅ DNS resolution works in libguestfs appliance
- ✅ Package installation succeeds
- ✅ No resolv.conf workarounds needed

---

#### ☐ Task 6.3: Consider alternative solutions

**Long-term options to research:**

1. **Custom libguestfs appliance with resolv.conf:**
   - Build custom supermin appliance with /etc/resolv.conf
   - Distribute as part of build infrastructure

2. **Use virt-customize instead of virt-sysprep:**
   - virt-customize may handle DNS differently
   - Research compatibility

3. **Container-based builds:**
   - Use Docker/Podman for customization instead of libguestfs
   - Mount qcow2 with nbd/qemu-nbd

**Action:** Research and document feasibility of alternatives

---

## Image-Specific Implementation Matrix

### Distributions Requiring customize Re-enablement

| Image | env.sh Path | virt.sysprep Path | Package Manager | SSH Service | Status | Notes |
|-------|-------------|-------------------|-----------------|-------------|--------|-------|
| **Kali Linux** | `images/kali-linux/env.sh` | `images/kali-linux/virt.sysprep` | APT | ssh | ✅ Complete | Reference implementation |
| **Debian 13** | `images/debian-13/env.sh` | `images/debian-13/virt.sysprep` | APT | ssh | ✅ Complete | Working |
| **Ubuntu 24.04** | `images/ubuntu-24-04/env.sh` | `images/ubuntu-24-04/virt.sysprep` | APT | ssh | ✅ Complete | Working |
| **Fedora 42** | `images/fedora-42/env.sh` | `images/fedora-42/virt.sysprep` | DNF | sshd | ☐ TODO | Needs customize enabled |
| **AlmaLinux 10** | `images/almalinux-10/env.sh` | `images/almalinux-10/virt.sysprep` | DNF | sshd | ☐ TODO | Needs customize enabled |
| **CentOS 10** | `images/centos-10/env.sh` | `images/centos-10/virt.sysprep` | DNF | sshd | ☐ TODO | Needs customize enabled |
| **Rocky 10** | `images/rocky-10/env.sh` | `images/rocky-10/virt.sysprep` | DNF | sshd | ☐ TODO | Needs customize enabled |
| **openSUSE Leap 16** | `images/opensuse-leap-16/env.sh` | `images/opensuse-leap-16/virt.sysprep` | Zypper | sshd | ☐ TODO | Needs customize enabled |
| **openSUSE Tumbleweed** | `images/opensuse-tumbleweed/env.sh` | `images/opensuse-tumbleweed/virt.sysprep` | Zypper | sshd | ☐ TODO | Rolling release, needs customize enabled |
| **Arch Linux** | `images/archlinux-latest/env.sh` | `images/archlinux-latest/virt.sysprep` | Pacman | sshd | ☐ TODO | Rolling release, needs customize enabled |

---

### Distributions Exempted from customize (No Action Needed)

| Image | Reason | Build Method | Notes |
|-------|--------|--------------|-------|
| **VyOS Rolling** | Custom Docker build | BUILD_METHOD=vyos-build | Uses vyos-build container, no virt-sysprep |
| **Talos Linux 1.11** | Immutable OS | Image Factory | Pre-built from Image Factory, minimal customization |
| **Fedora CoreOS 42** | Container-optimized | Ignition | Uses Ignition for configuration, may not need virt-sysprep customize |
| **OpenWrt 24** | Embedded router OS | Minimal image | Check if packages needed, may skip customize |
| **FreeBSD 15** | Different OS family | BSD tooling | Validate separately, may not use systemd |

**Action for exempt images:**
- ☐ Document build method for each
- ☐ Verify no virt-sysprep customize needed
- ☐ Test current build process still works with Ubuntu 22.04 runners

---

### Package Installation Matrix (by Distribution)

| Distribution | Package Manager | Update Command | Install Syntax | Package Names | Service Names |
|--------------|-----------------|----------------|----------------|---------------|---------------|
| **Debian/Ubuntu/Kali** | APT | `update` | `install pkg1,pkg2,pkg3` | cloud-init, cloud-initramfs-growroot, openssh-server, qemu-guest-agent | ssh, qemu-guest-agent |
| **Fedora** | DNF | `update` | `install pkg1 pkg2 pkg3` | cloud-init, cloud-utils-growpart, openssh-server, qemu-guest-agent | sshd, qemu-guest-agent |
| **AlmaLinux/CentOS/Rocky** | DNF | `update` | `install pkg1 pkg2 pkg3` | cloud-init, cloud-utils-growpart, openssh-server, qemu-guest-agent | sshd, qemu-guest-agent |
| **openSUSE** | Zypper | `update` or `refresh` | `install pkg1 pkg2 pkg3` | cloud-init, openssh, qemu-guest-agent | sshd, qemu-guest-agent |
| **Arch Linux** | Pacman | `update` or `-Syu` | `install pkg1 pkg2 pkg3` | cloud-init, openssh, qemu-guest-agent | sshd, qemu-guest-agent |

**virt.sysprep syntax reference:**
```bash
# APT (Debian/Ubuntu/Kali) - comma-separated
update
install cloud-init,cloud-initramfs-growroot,openssh-server,qemu-guest-agent,python3,tmux,git,vim,btop

# DNF (Fedora/RHEL/Alma/Rocky) - space-separated
update
install cloud-init cloud-utils-growpart openssh-server qemu-guest-agent python3 tmux git vim btop

# Zypper (openSUSE) - space-separated
update
install cloud-init openssh qemu-guest-agent python3 tmux git vim btop

# Pacman (Arch) - space-separated
update
install cloud-init openssh qemu-guest-agent python tmux git vim btop
```

---

## Validation Checklist

### Per-Image Build Validation

For each distribution image, complete the following checklist:

#### **Image: ___________________** (fill in distribution name)

##### Build Stage
- ☐ env.sh updated with `customize` in VIRT_SYSPREP_OPERATIONS
- ☐ virt.sysprep file exists with package installation commands
- ☐ virt.sysprep includes resolv.conf creation (run-command sh -c)
- ☐ Package manager syntax verified for distribution
- ☐ Service names verified for distribution (ssh vs sshd)
- ☐ Cloud-init services explicitly enabled (cloud-init-local, cloud-init-network, cloud-config, cloud-final)
- ☐ Local build test passed (`./hack/customize.sh`)
- ☐ No DNS resolution errors in build logs
- ☐ Package installation succeeded
- ☐ Service enablement succeeded (no "does not exist" errors)
- ☐ QCOW2 image created successfully
- ☐ Image size is reasonable (within expected range)

##### CircleCI Validation
- ☐ CircleCI workflow triggered
- ☐ Build logs show "Updating packages"
- ☐ apt-get/dnf/zypper/pacman update succeeded
- ☐ Package installation succeeded
- ☐ No "Temporary failure resolving" errors
- ☐ Service enablement logs show "Synchronizing state" for all services
- ☐ virt-sparsify completed
- ☐ Docker image built successfully
- ☐ Docker image pushed to DockerHub
- ☐ Image tagged correctly (version + latest)

##### VM Deployment Validation
- ☐ Example deployment files exist (VM manifest, userdata, deploy.sh)
- ☐ VM manifest uses correct container image reference
- ☐ Cloud-init userdata includes required configuration
- ☐ VM deploys successfully (`kubectl apply -f ...`)
- ☐ DataVolume imports successfully
- ☐ VMI starts and reaches Running state
- ☐ Cloud-init completes without errors
- ☐ SSH access works with injected public key
- ☐ qemu-guest-agent is running (`systemctl status qemu-guest-agent`)
- ☐ Cloud-init services are active (cloud-init-local, cloud-init-network, cloud-config, cloud-final)
- ☐ Installed packages are present (`which cloud-init git tmux vim`)
- ☐ Network connectivity works (ping 8.8.8.8, curl example.com)

##### Documentation Validation
- ☐ README.md updated with image status
- ☐ Example README exists for deployment
- ☐ Quick start guide is accurate
- ☐ Troubleshooting section addresses common issues

##### Regression Testing
- ☐ No breakage of previously working features
- ☐ Existing VMs can still be deployed
- ☐ Image size hasn't increased significantly
- ☐ Build time is acceptable

---

### Overall Project Validation

#### Infrastructure
- ☐ All CircleCI executors use ubuntu-2204:2025.09.1
- ☐ No ubuntu-2404 references remain in .circleci/config.yml
- ☐ CircleCI workflows configured for all distributions
- ☐ DockerHub credentials configured correctly

#### Code Quality
- ☐ All env.sh files follow consistent formatting
- ☐ All virt.sysprep files include resolv.conf creation
- ☐ Package installation commands use correct syntax
- ☐ Service enablement uses correct service names
- ☐ Cloud-init services use correct names (cloud-init-network.service, not cloud-init.service)
- ☐ No hardcoded values that should be variables

#### Testing
- ☐ At least one successful build per distribution family (Debian, RHEL, SUSE, Arch)
- ☐ At least one successful VM deployment per distribution family
- ☐ SSH access validated for all deployed VMs
- ☐ Cloud-init validated for all deployed VMs

#### Documentation
- ☐ TASKS document (this file) is complete and accurate
- ☐ README.md reflects all supported distributions
- ☐ libguestfs DNS issue documented
- ☐ Deployment examples exist for all distributions
- ☐ Troubleshooting guide addresses DNS issues

---

## Rollback Plan

### If DNS Resolution Still Fails on Ubuntu 22.04

**Symptoms:**
- "Temporary failure resolving" errors persist
- Package installation fails in virt-sysprep
- Builds succeed but VMs don't have packages installed

**Actions:**

1. **Verify Ubuntu 22.04 is actually being used:**
   ```bash
   # Check CircleCI build logs for:
   cat /etc/os-release
   # Should show Ubuntu 22.04, not 24.04
   ```

2. **Check libguestfs version:**
   ```bash
   # In CircleCI logs, look for:
   libguestfs: launch: version=X.XX.X
   # Ensure version matches Ubuntu 22.04's packaged version
   ```

3. **Rollback customize operation:**
   ```bash
   # In affected image's env.sh:
   VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files
   # Remove 'customize' temporarily
   ```

4. **Manual package installation workaround:**
   - Install packages via cloud-init userdata instead
   - Update example userdata files with package installation
   - Less efficient but functional

---

### If Ubuntu 22.04 Runner Unavailable

**Symptoms:**
- CircleCI error: "unsupported image version"
- CircleCI deprecates ubuntu-2204 executor

**Actions:**

1. **Research self-hosted runners:**
   - Set up self-hosted CircleCI runners on Ubuntu 22.04
   - https://circleci.com/docs/runner-overview/

2. **Alternative CI platforms:**
   - GitHub Actions with ubuntu-22.04 runners
   - GitLab CI with Docker executor and Ubuntu 22.04 image

3. **Container-based build approach:**
   - Use Docker-in-Docker for image customization
   - Mount qcow2 with qemu-nbd
   - Run package installation in container

---

### If Image Build Breaks Other Functionality

**Symptoms:**
- VM won't boot
- Cloud-init hangs or fails
- Network doesn't work
- Performance degradation

**Actions:**

1. **Revert to last known good commit:**
   ```bash
   git revert <commit-hash>
   git push
   ```

2. **Isolate the problem:**
   - Test with minimal virt.sysprep (only update, no install)
   - Test with single package installation
   - Compare working (Kali) vs broken image configs

3. **Check for distribution-specific issues:**
   - Review package manager logs in VM
   - Check cloud-init logs: `/var/log/cloud-init-output.log`
   - Verify systemd services: `systemctl status`

---

## Success Criteria

### Definition of Done

This project is considered complete when:

1. ✅ All applicable distributions have `customize` operation enabled in env.sh
2. ✅ All applicable distributions successfully build in CircleCI
3. ✅ All applicable distributions publish to DockerHub
4. ✅ At least one VM deployment tested per distribution family
5. ✅ SSH access works for all tested VMs
6. ✅ Cloud-init completes successfully for all tested VMs
7. ✅ qemu-guest-agent is running on all tested VMs
8. ✅ All cloud-init services are enabled and active
9. ✅ Documentation updated with current status
10. ✅ Rollback plan tested and validated

### Metrics for Success

- **Build Success Rate:** 100% for all enabled distributions
- **VM Boot Success Rate:** 100% for all tested distributions
- **Cloud-init Success Rate:** 100% for all tested distributions
- **DNS Resolution Errors:** 0 across all builds
- **Service Enablement Errors:** 0 across all builds
- **Build Time:** Within acceptable range (baseline + 20% max)
- **Image Size:** Within acceptable range (baseline + 10% max)

---

## Appendix A: File Locations Reference

### Configuration Files

```
.circleci/config.yml              # CircleCI runner version configuration
hack/customize.sh                  # Main build script with DNS checks
hack/update.sh                     # Checksum update automation
bake.hcl                          # Docker Buildx configuration
README.md                         # Main documentation
```

### Per-Distribution Files

```
images/kali-linux/env.sh          # Build configuration (reference implementation)
images/kali-linux/virt.sysprep    # Customization commands (reference implementation)
images/debian-13/env.sh
images/debian-13/virt.sysprep
images/ubuntu-24-04/env.sh
images/ubuntu-24-04/virt.sysprep
images/fedora-42/env.sh
images/fedora-42/virt.sysprep
images/almalinux-10/env.sh
images/almalinux-10/virt.sysprep
images/centos-10/env.sh
images/centos-10/virt.sysprep
images/rocky-10/env.sh
images/rocky-10/virt.sysprep
images/opensuse-leap-16/env.sh
images/opensuse-leap-16/virt.sysprep
images/opensuse-tumbleweed/env.sh
images/opensuse-tumbleweed/virt.sysprep
images/archlinux-latest/env.sh
images/archlinux-latest/virt.sysprep
```

### Example Deployment Files

```
examples/kali/deploy.sh           # Automated deployment script (reference)
examples/kali/kali-linux-userdata.yaml
examples/kali/kali-linux-vdi-xrdp-gnome-br0-containerdisk.yaml
examples/kali/README.md

# Similar structure for other distributions:
examples/debian/
examples/ubuntu/
examples/fedora/
examples/almalinux/
examples/centos/
examples/rocky/
examples/opensuse-leap/
examples/opensuse-tumbleweed/
examples/archlinux/
```

---

## Appendix B: Key Commits Reference

| Commit | Description | Files Changed |
|--------|-------------|---------------|
| `3b204e5` | fix(debian,ubuntu,kali): enable correct cloud-init systemd services | `images/*/virt.sysprep` |
| `87cc74c` | fix(debian,ubuntu): match Kali operations and fix resolv.conf creation | `images/debian-13/env.sh`, `images/ubuntu-24-04/env.sh`, `images/*/virt.sysprep` |
| `bd25b70` | fix(debian,ubuntu): use run-command for resolv.conf creation | `images/debian-13/virt.sysprep`, `images/ubuntu-24-04/virt.sysprep` |
| `e92f09a` | fix(debian,ubuntu): re-enable customize operation with DNS resolution | `images/debian-13/*`, `images/ubuntu-24-04/*` |
| `52b799d` | fix(ci): downgrade CircleCI runners to Ubuntu 22.04 for libguestfs compatibility | `.circleci/config.yml` |

---

## Appendix C: Contact and Resources

### Project Resources

- **Repository:** https://github.com/containercraft/kmi
- **DockerHub:** https://hub.docker.com/u/containercraft
- **Issues:** https://github.com/containercraft/kmi/issues
- **CircleCI:** https://app.circleci.com/pipelines/github/containercraft/kmi

### External Resources

- **libguestfs Documentation:** https://libguestfs.org/
- **virt-sysprep Manual:** https://libguestfs.org/virt-sysprep.1.html
- **KubeVirt Documentation:** https://kubevirt.io/user-guide/
- **Cloud-init Documentation:** https://cloudinit.readthedocs.io/
- **Cloud-init Repository:** https://github.com/canonical/cloud-init

### Support Channels

- **GitHub Issues:** For bug reports and feature requests
- **GitHub Discussions:** For questions and community support
- **CircleCI Support:** For CI/CD infrastructure issues

---

## Document Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-10-25 | 1.0 | Claude Code | Initial document creation with complete DNS resolution remediation plan |
| 2025-10-25 | 1.1 | Claude Code | Updated with tested implementation and cloud-init service configuration |

---

## Notes

### Systems Thinking Summary

This remediation affects the entire KMI build pipeline:

1. **Infrastructure Layer (CircleCI):**
   - Ubuntu 22.04 runners provide libguestfs compatibility
   - All executors (amd64, arm64) must use same version

2. **Build Layer (customize.sh):**
   - DNS checks remain for defensive programming
   - Works with Ubuntu 22.04's traditional resolv.conf

3. **Distribution Layer (env.sh):**
   - Each distribution needs `customize` operation enabled
   - Different distributions have different package managers

4. **Customization Layer (virt.sysprep):**
   - resolv.conf creation for defensive programming
   - Distribution-specific package names and syntax
   - Distribution-specific service names (ssh vs sshd)
   - Explicit cloud-init service enablement for validation

5. **Deployment Layer (KubeVirt):**
   - VMs must have cloud-init, SSH, qemu-guest-agent installed
   - Services must be enabled for proper operation
   - All cloud-init stages must be active

6. **Documentation Layer:**
   - README reflects current capabilities
   - Example deployments guide users
   - Troubleshooting helps debug issues

### High-Level Implementation Strategy

1. **Start with reference implementation:** Kali Linux, Debian 13, Ubuntu 24.04 are working
2. **Group by distribution family:** Debian-based (complete), RPM-based, SUSE, Arch
3. **Validate incrementally:** Test each distribution before moving to next
4. **Document exceptions:** FreeBSD, VyOS, Talos, etc. have different requirements
5. **Maintain consistency:** Use same patterns across all distributions where possible
6. **Explicit service enablement:** Enable services explicitly for fail-fast validation
7. **Cloud-init best practices:** Use correct service names (cloud-init-network.service, not cloud-init.service)

---

**End of Document**
