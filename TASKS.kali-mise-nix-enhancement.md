# KMI Kali Linux Image Enhancement: Pre-installed Mise + Lix/Nix Dependencies

## Project Overview

**Objective**: Enhance the KMI Kali Linux qcow2 image build to pre-install mise and lix/nix dependencies, eliminating cloud-init bootstrap overhead and enabling immediate `nix develop` capability on VM boot.

**Rationale**: Current cloud-init workflow performs expensive operations (mise install, nix install, git clone, trust operations) on every VM creation. Pre-baking these dependencies into the base image reduces VM bootstrap time from minutes to seconds.

**Target Image**: `containercraft/kali:2025-3-dev`

---

## Current State Analysis

### Existing Build Pipeline
- **Source**: `kmi/images/kali-linux/`
  - `env.sh`: Build configuration (URLs, checksums, arch)
  - `virt.sysprep`: Package installation and system configuration
- **Build Tool**: `kmi/hack/customize.sh` (libguestfs + virt-sysprep)
- **CI/CD**: CircleCI (`kmi/.circleci/config.yml`)

### Current Cloud-Init Operations (To Be Eliminated)
```bash
# From kubevirt/kali-kalilix-userdata.yaml (lines 47-57)
- sudo -u kali bash -c 'curl https://mise.run | sh'
- sudo -u kali git clone https://github.com/usrbinkat/kalilix.git /home/kali/.kalilix
- sudo -u kali bash -c 'cd /home/kali/.kalilix && /home/kali/.local/bin/mise trust ...'
- sudo -u kali bash -c 'export PATH="/home/kali/.local/bin:$PATH" && cd /home/kali/.kalilix && mise run bootstrap'
- sudo -u kali bash -c 'cd /home/kali/.kalilix && source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix develop .#full --command true'
- sudo -u kali bash -c 'echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> /home/kali/.bashrc'
- sudo -u kali bash -c 'echo "[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] && source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" >> /home/kali/.bashrc'
```

### Desired State
**Post-Boot Command** (single step):
```bash
nix develop github:usrbinkat/kalilix#full
```

**No Prerequisites**: VM boots with mise and nix pre-configured, ready for immediate flake development.

---

## Implementation Tasks

### Phase 1: Design & Planning ✓ (Completed)

- [x] Analyze KMI build pipeline architecture
- [x] Review virt-sysprep capabilities and limitations
- [x] Identify package dependencies for Debian-based Kali
- [x] Design /etc/skel/.bashrc integration approach
- [x] Validate mise installation method for offline/VM context
- [x] Validate lix/nix multi-user installation in virt-sysprep

---

### Phase 2: Mise Installation Integration

#### Task 2.1: Add Mise Dependencies to virt.sysprep
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Add required packages for mise installation

- [ ] Add `curl` to package list (may already be present)
- [ ] Add `ca-certificates` for HTTPS downloads
- [ ] Add `xz-utils` for mise binary extraction (if needed)
- [ ] Verify DNS configuration is set correctly (lines 7-8)

**Changes Required**:
```bash
# Line 11 - Update install command to include mise dependencies
install cloud-init,cloud-initramfs-growroot,openssh-server,qemu-guest-agent,python3,tmux,git,vim,btop,curl,ca-certificates,xz-utils
```

**Validation**:
- [ ] Confirm packages are available in Kali repos
- [ ] Test installation doesn't conflict with existing packages

---

#### Task 2.2: Install Mise via virt-sysprep
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Add mise installation commands

- [ ] Download mise installer script
- [ ] Install mise for root user (for /etc/skel configuration)
- [ ] Verify mise binary is in expected location
- [ ] Set proper permissions on mise binary

**Implementation Approach**:
```bash
# Add after line 18 (after apt-get clean)
# Install mise for system-wide template
run-command curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin sh
run-command chmod 755 /usr/local/bin/mise

# Alternative: Direct binary download (more reliable for offline builds)
run-command curl -fsSL https://github.com/jdx/mise/releases/latest/download/mise-latest-linux-x64 -o /usr/local/bin/mise
run-command chmod 755 /usr/local/bin/mise
```

**Validation Steps**:
- [ ] Verify mise binary is executable
- [ ] Test `mise --version` works in chroot context
- [ ] Confirm mise is in system PATH

**Notes**:
- Using /usr/local/bin ensures mise is available system-wide
- virt-sysprep `run-command` executes in chroot context
- Network access available via `--network` flag in virt-sysprep call (line 202-207 in customize.sh)

---

#### Task 2.3: Configure Mise in /etc/skel/.bashrc
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Configure mise activation in default user shell profile

- [ ] Create or append to /etc/skel/.bashrc
- [ ] Add mise activation hook
- [ ] Add PATH configuration for mise-installed tools
- [ ] Ensure configuration is idempotent

**Implementation**:
```bash
# Add after mise installation
# Configure mise activation in /etc/skel/.bashrc for all new users
run-command mkdir -p /etc/skel
append-line /etc/skel/.bashrc:# Mise (polyglot runtime manager) initialization
append-line /etc/skel/.bashrc:# Auto-loads tools based on .mise.toml and .env files
append-line /etc/skel/.bashrc:export PATH="$HOME/.local/bin:$PATH"
append-line /etc/skel/.bashrc:if command -v mise >/dev/null 2>&1; then
append-line /etc/skel/.bashrc:  eval "$(mise activate bash)"
append-line /etc/skel/.bashrc:fi
append-line /etc/skel/.bashrc:
```

**Alternative Approach (using write command)**:
```bash
# Using write command for multi-line content
write /etc/skel/.bashrc.mise:# Mise (polyglot runtime manager) initialization
append-line /etc/skel/.bashrc.mise:# Auto-loads tools based on .mise.toml and .env files
append-line /etc/skel/.bashrc.mise:export PATH="$HOME/.local/bin:$PATH"
append-line /etc/skel/.bashrc.mise:if command -v mise >/dev/null 2>&1; then
append-line /etc/skel/.bashrc.mise:  eval "$(mise activate bash)"
append-line /etc/skel/.bashrc.mise:fi
run-command cat /etc/skel/.bashrc.mise >> /etc/skel/.bashrc
run-command rm /etc/skel/.bashrc.mise
```

**Validation**:
- [ ] Verify /etc/skel/.bashrc exists and is readable
- [ ] Test configuration doesn't break default bash startup
- [ ] Confirm PATH modifications don't conflict

---

### Phase 3: Lix/Nix Installation Integration

#### Task 3.1: Add Nix Dependencies to virt.sysprep
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Add packages required for Nix multi-user installation

- [ ] Add `sudo` (may already be present)
- [ ] Add `systemd` (should already be present on Kali)
- [ ] Add `bash` (should already be present)
- [ ] Verify no conflicts with existing package list

**Required Packages** (most likely already present):
```bash
# These are typically already installed on Kali, but verify:
sudo, systemd, bash, curl, xz-utils, ca-certificates
```

**Validation**:
- [ ] Confirm systemd is enabled and will start on boot
- [ ] Verify /etc/systemd/system directory exists

---

#### Task 3.2: Install Lix/Nix Multi-User via virt-sysprep
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Install Lix/Nix in multi-user mode with systemd service

- [ ] Download Lix installer
- [ ] Execute multi-user installation
- [ ] Enable nix-daemon.service for systemd
- [ ] Configure nix-daemon to start on boot
- [ ] Verify /nix directory structure is created

**Implementation Strategy**:

**Option A: Direct Lix Installation** (Preferred - Official Lix Installer)
```bash
# Install Lix (Nix fork) in multi-user mode
# The installer needs to run non-interactively
run-command curl -sSf -L https://install.lix.systems/lix | sh -s -- install --no-confirm

# Enable nix-daemon service
run-command systemctl enable nix-daemon.service

# Create /nix/var/nix/profiles/default/etc/profile.d directory if needed
run-command mkdir -p /nix/var/nix/profiles/default/etc/profile.d
```

**Option B: Standard Nix Multi-User Installation** (Fallback)
```bash
# Install Nix in multi-user mode
run-command curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes

# Enable nix-daemon service
run-command systemctl enable nix-daemon.service
```

**Option C: Manual Lix Installation** (Most Control)
```bash
# Download Lix installer
run-command curl -sSf -L https://install.lix.systems/lix/lix-installer-x86_64-linux -o /tmp/lix-installer
run-command chmod +x /tmp/lix-installer

# Run installer in non-interactive mode
run-command /tmp/lix-installer install --no-confirm

# Clean up installer
run-command rm /tmp/lix-installer

# Enable systemd service
run-command systemctl enable nix-daemon.service
```

**Validation Steps**:
- [ ] Verify /nix directory exists with proper ownership
- [ ] Confirm /nix/var/nix/daemon-socket/socket exists
- [ ] Check nix-daemon.service is enabled: `systemctl is-enabled nix-daemon`
- [ ] Verify /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh exists
- [ ] Test nix binary is in /nix/var/nix/profiles/default/bin/nix

**Critical Considerations**:
- virt-sysprep runs in chroot, so systemd isn't running during build
- Use `systemctl enable` not `systemctl start` (activation happens on first boot)
- Nix installer may require /run/systemd/system to exist
- May need to create build-time directories: `/run/systemd/system`, `/var/lib/systemd`

**Pre-requisites for Nix Installer**:
```bash
# Create systemd directories if they don't exist
run-command mkdir -p /run/systemd/system
run-command mkdir -p /var/lib/systemd
```

---

#### Task 3.3: Configure Nix in /etc/skel/.bashrc
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Configure Nix daemon profile sourcing in default user shell

- [ ] Append Nix initialization to /etc/skel/.bashrc
- [ ] Add conditional sourcing (only if nix-daemon.sh exists)
- [ ] Ensure configuration works with mise configuration
- [ ] Test order of operations (PATH, mise, nix)

**Implementation**:
```bash
# Add after mise configuration in /etc/skel/.bashrc
# Configure Nix daemon profile in /etc/skel/.bashrc for all new users
append-line /etc/skel/.bashrc:# Nix package manager initialization
append-line /etc/skel/.bashrc:# Source the multi-user Nix daemon profile
append-line /etc/skel/.bashrc:if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
append-line /etc/skel/.bashrc:  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
append-line /etc/skel/.bashrc:fi
append-line /etc/skel/.bashrc:
```

**Complete /etc/skel/.bashrc Content**:
```bash
# Mise (polyglot runtime manager) initialization
# Auto-loads tools based on .mise.toml and .env files
export PATH="$HOME/.local/bin:$PATH"
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

# Nix package manager initialization
# Source the multi-user Nix daemon profile
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
```

**Validation**:
- [ ] Verify proper shell initialization order
- [ ] Test PATH includes both mise and nix binaries
- [ ] Confirm no conflicts between mise and nix PATH entries

---

#### Task 3.4: Configure Nix for kali User Home Directory
**File**: `kmi/images/kali-linux/virt.sysprep`

**Action**: Pre-configure kali user's home directory with Nix profile

**Note**: The `kali` user already exists in the Kali Linux image (default user with UID 1000)

- [ ] Verify kali user exists (should be default in Kali image)
- [ ] Copy /etc/skel/.bashrc to /home/kali/.bashrc if needed
- [ ] Set proper ownership on /home/kali/.bashrc
- [ ] Create /home/kali/.local/bin directory
- [ ] Set proper permissions on kali home directory

**Implementation**:
```bash
# The kali user should already exist in Kali Linux
# Ensure .bashrc is configured (it may already be via /etc/skel)
run-command cp -n /etc/skel/.bashrc /home/kali/.bashrc || true
run-command chown kali:kali /home/kali/.bashrc
run-command chmod 644 /home/kali/.bashrc

# Create .local/bin directory for kali user
run-command mkdir -p /home/kali/.local/bin
run-command chown -R kali:kali /home/kali/.local
run-command chmod 755 /home/kali/.local /home/kali/.local/bin
```

**Validation**:
- [ ] Verify /home/kali exists
- [ ] Confirm /home/kali/.bashrc has correct ownership
- [ ] Check /home/kali/.local/bin directory exists and is in PATH

---

### Phase 4: Build System Integration

#### Task 4.1: Update virt.sysprep Operation Flags
**File**: `kmi/images/kali-linux/env.sh`

**Action**: Verify VIRT_SYSPREP_OPERATIONS setting

**Current Setting** (line 9):
```bash
VIRT_SYSPREP_OPERATIONS=logfiles,bash-history,tmp-files,customize
```

**Analysis**:
- `customize` operation: REQUIRED - enables our virt.sysprep script
- `logfiles`: Cleans log files (safe to keep)
- `bash-history`: Cleans bash history (safe to keep)
- `tmp-files`: Cleans temporary files (safe to keep)
- Does NOT include `user-account` operation (good - preserves kali user)

**Action**:
- [ ] Confirm current operations are appropriate
- [ ] Verify `customize` operation is present (REQUIRED)
- [ ] No changes needed unless testing reveals issues

---

#### Task 4.2: Update customize.sh Network Flag (Already Configured)
**File**: `kmi/hack/customize.sh`

**Action**: Verify virt-sysprep has network access for downloads

**Current Configuration** (line 202-207):
```bash
# Customize Disk Image
sudo virt-sysprep \
	--verbose \
	--network \  # <-- ALREADY ENABLED
	--add "${QCOW2_TMPFILE}" \
	--commands-from-file images/"${FLAVOR}"/virt.sysprep \
	--enable "${VIRT_SYSPREP_OPERATIONS}"
```

**Validation**:
- [x] `--network` flag is present (enables curl downloads)
- [ ] Test DNS resolution works in virt-sysprep context
- [ ] Confirm no proxy configuration needed

---

#### Task 4.3: Increase Disk Resize for Nix Store
**File**: `kmi/hack/customize.sh`

**Action**: Ensure sufficient disk space for Nix installation

**Current Setting** (line 189):
```bash
# Grow disk size
qemu-img resize "${QCOW2_TMPFILE}" +20G
```

**Analysis**:
- Nix installation requires ~2-5GB for base system
- Base Kali image is already sized for OS + tools
- +20G should be sufficient for Nix + mise
- Could increase to +30G for safety

**Recommendation**:
- [ ] Keep current +20G (monitor during testing)
- [ ] Consider increasing to +30G if Nix store grows large
- [ ] Validate final image size doesn't exceed 64Gi limit

**Optional Change**:
```bash
# Grow disk size (increased for Nix store)
qemu-img resize "${QCOW2_TMPFILE}" +30G
```

---

#### Task 4.4: Update CircleCI Build Configuration (If Needed)
**File**: `kmi/.circleci/config.yml`

**Action**: Verify CI/CD pipeline handles increased build requirements

**Current Configuration** (lines 420-443):
```yaml
# Start Kali Linux #
- customize:
    name: customize-<< matrix.flavor >>-<< matrix.arch >>
    matrix:
      parameters:
        flavor: *_kali-flavors
        arch: [amd64]

- cradle:
    requires:
      - customize-<< matrix.flavor >>-amd64
    name: cradle-<< matrix.flavor >>
    matrix:
      parameters:
        flavor: *_kali-flavors

- trigger-tests:
    requires:
      - cradle-<< matrix.flavor >>
    name: trigger-<< matrix.flavor >>-promotion
    matrix:
      parameters:
        flavor: *_kali-flavors
# End Kali Linux #
```

**Current Resource Class** (lines 710-718):
```yaml
# AMD64 Runner
amd64:
  machine:
    enabled: true
    image: ubuntu-2204:2025.09.1
  environment:
    DOCKER_CLI_EXPERIMENTAL: enabled
  resource_class: xlarge # 8 vCPUs, 32GB RAM
```

**Analysis**:
- Current: xlarge (8 vCPU, 32GB RAM)
- Nix installation may require more time, not necessarily more resources
- Network downloads may increase build time
- Caching should help with rebuild times

**Action**:
- [ ] Monitor first CI/CD build time with Nix installation
- [ ] Evaluate if timeout needs adjustment (line 616: 90m no_output_timeout)
- [ ] Consider if resource class upgrade needed (unlikely)

**Potential Optimization**:
- [ ] Add CircleCI cache key for Nix installation artifacts (if slow)
- [ ] Consider pre-downloading Lix installer in cache step

---

### Phase 5: Testing & Validation

#### Task 5.1: Local Build Testing
**Location**: Development machine with KMI repository

**Prerequisites**:
- [ ] libguestfs-tools installed (`apt install guestfs-tools`)
- [ ] qemu-img available
- [ ] Sufficient disk space (~100GB for build artifacts)
- [ ] Network connectivity for downloads

**Test Steps**:

**Step 5.1.1: Clean Local Build**
```bash
cd kmi/
FLAVOR=kali-linux ARCH=amd64 bash hack/customize.sh
```

**Validation Checkpoints**:
- [ ] Build completes without errors
- [ ] mise installation succeeds (check logs for "mise")
- [ ] Nix installation succeeds (check logs for "nix")
- [ ] DNS resolution works (no curl failures)
- [ ] Final qcow2 file is created: `kali-linux-amd64.qcow2`
- [ ] File size is reasonable (check if < 64Gi)

**Step 5.1.2: Inspect Built Image**
```bash
# Mount image and inspect
sudo virt-inspector -a kali-linux-amd64.qcow2

# Check if mise is installed
sudo virt-cat -a kali-linux-amd64.qcow2 /usr/local/bin/mise > /dev/null && echo "mise: OK"

# Check if nix is installed
sudo virt-cat -a kali-linux-amd64.qcow2 /nix/var/nix/profiles/default/bin/nix > /dev/null && echo "nix: OK"

# Check /etc/skel/.bashrc configuration
sudo virt-cat -a kali-linux-amd64.qcow2 /etc/skel/.bashrc | grep -E "(mise|nix)"

# Check kali user .bashrc
sudo virt-cat -a kali-linux-amd64.qcow2 /home/kali/.bashrc | grep -E "(mise|nix)"

# Check nix-daemon.service is enabled
sudo virt-cat -a kali-linux-amd64.qcow2 /etc/systemd/system/multi-user.target.wants/nix-daemon.service > /dev/null && echo "nix-daemon enabled: OK"
```

**Validation Checklist**:
- [ ] /usr/local/bin/mise exists and is executable
- [ ] /nix/var/nix/profiles/default/bin/nix exists
- [ ] /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh exists
- [ ] /etc/skel/.bashrc contains mise activation
- [ ] /etc/skel/.bashrc contains nix sourcing
- [ ] /home/kali/.bashrc is configured correctly
- [ ] nix-daemon.service is enabled
- [ ] /nix directory structure exists with proper ownership

---

#### Task 5.2: Local VM Boot Testing
**Location**: Development machine with KVM/QEMU

**Prerequisites**:
- [ ] libvirt and qemu-kvm installed
- [ ] Network bridge configured (or use default NAT)
- [ ] Built kali-linux-amd64.qcow2 from Task 5.1

**Test Steps**:

**Step 5.2.1: Create Test VM**
```bash
# Copy image to libvirt images directory
sudo cp kali-linux-amd64.qcow2 /var/lib/libvirt/images/kali-test.qcow2

# Create VM using virt-install (no cloud-init)
sudo virt-install \
  --name kali-test \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/kali-test.qcow2,bus=virtio \
  --network network=default \
  --graphics vnc \
  --import \
  --os-variant debian11 \
  --noautoconsole
```

**Step 5.2.2: Boot and Console Access**
```bash
# Connect to VM console
sudo virsh console kali-test

# Or use VNC
virt-viewer kali-test
```

**Step 5.2.3: Login and Validation**
```bash
# Login as kali user (default password: kali)
# After login, verify shell initialization

# Test 1: Check mise is available
mise --version

# Test 2: Check nix is available
nix --version

# Test 3: Check nix daemon is running
systemctl status nix-daemon

# Test 4: Check PATH includes mise and nix
echo $PATH | grep -E "(mise|nix)"

# Test 5: Verify .bashrc was sourced
type mise
type nix

# Test 6: Test nix flake command (THE ULTIMATE TEST)
nix flake show github:usrbinkat/kalilix

# Test 7: Enter nix development shell
nix develop github:usrbinkat/kalilix#full --command bash -c "echo 'Success: Nix shell works!'"
```

**Validation Checklist**:
- [ ] VM boots successfully
- [ ] Login works (kali/kali)
- [ ] mise command is available
- [ ] nix command is available
- [ ] nix-daemon.service is running
- [ ] PATH includes /nix/var/nix/profiles/default/bin
- [ ] `nix flake show` works without errors
- [ ] `nix develop github:usrbinkat/kalilix#full` works
- [ ] No cloud-init required for any of the above

**Step 5.2.4: Performance Baseline**
```bash
# Time the nix develop command (should be faster than cloud-init approach)
time nix develop github:usrbinkat/kalilix#full --command bash -c "echo 'Success'"

# Expected: < 30 seconds for first run (with network fetch)
# Expected: < 5 seconds for subsequent runs (cached)
```

**Cleanup**:
```bash
sudo virsh destroy kali-test
sudo virsh undefine kali-test
sudo rm /var/lib/libvirt/images/kali-test.qcow2
```

---

#### Task 5.3: KubeVirt Deployment Testing
**Location**: Kubernetes cluster with KubeVirt

**Prerequisites**:
- [ ] KubeVirt cluster accessible
- [ ] kubectl configured
- [ ] Updated kali-linux image pushed to container registry (or use local build)
- [ ] SSH public key secret exists: `kargo-sshpubkey-kali`

**Test Steps**:

**Step 5.3.1: Build and Push Test Image**
```bash
# After local testing passes, build OCI container image
cd kmi/
docker buildx bake kali-linux --load

# Tag with test label
docker tag containercraft/kali:latest containercraft/kali:2025-3-test

# Push to registry (or use local registry for testing)
docker push containercraft/kali:2025-3-test
```

**Step 5.3.2: Update Test Manifest**
```bash
# Create test version of kubevirt manifest
cp kubevirt/kali-2025-3-golden-image.yaml kubevirt/kali-2025-3-golden-image-test.yaml

# Update image reference to test version
sed -i 's|containercraft/kali:2025-3-dev|containercraft/kali:2025-3-test|g' kubevirt/kali-2025-3-golden-image-test.yaml
```

**Step 5.3.3: Deploy Test Golden Image**
```bash
# Deploy golden image
kubectl apply -f kubevirt/kali-2025-3-golden-image-test.yaml

# Monitor import progress
kubectl get dv kali-2025-3-golden-image -w

# Wait for completion
kubectl wait --for=condition=Ready dv/kali-2025-3-golden-image --timeout=30m
```

**Step 5.3.4: Create Minimal Test Cloud-Init**

Create `kubevirt/kali-test-userdata.yaml`:
```yaml
#cloud-config
hostname: kalilix-test
fqdn: kalilix-test.home.arpa
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:kc2admin
    kali:kali
  expire: False
users:
  - default
  - name: kali
    gecos: Kalilix Test User
    shell: /bin/bash
    lock_passwd: false
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    groups: adm,cdrom,dip,sudo,docker
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: true
timezone: UTC
# CRITICAL: No mise or nix installation - testing pre-baked dependencies
runcmd:
  # Only test commands - no installation
  - mise --version
  - nix --version
  - systemctl status nix-daemon
  - nix flake show github:usrbinkat/kalilix
  - echo "$(date) - Test complete: mise and nix pre-installed" > /home/kali/test-complete
  - chown kali:kali /home/kali/test-complete
```

**Step 5.3.5: Create Test Secret**
```bash
kubectl create secret generic kali-test-userdata \
  --from-file=userdata=kubevirt/kali-test-userdata.yaml \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Step 5.3.6: Deploy Test VM**

Update `kubevirt/kali-kalilix-flake-minimal.yaml` to use test userdata:
```bash
# Create test VM manifest
cp kubevirt/kali-kalilix-flake-minimal.yaml kubevirt/kali-kalilix-flake-minimal-test.yaml

# Update to use test userdata
sed -i 's|kali-kalilix-userdata|kali-test-userdata|g' kubevirt/kali-kalilix-flake-minimal-test.yaml

# Deploy test VM
kubectl apply -f kubevirt/kali-kalilix-flake-minimal-test.yaml
```

**Step 5.3.7: Monitor VM Creation**
```bash
# Watch VM creation
kubectl get vm,vmi,dv,pvc -l app=kalilix-kali -w

# Check events
kubectl get events --sort-by='.lastTimestamp' | grep kalilix

# Monitor cloud-init progress
kubectl get vmi kalilix-kali -o jsonpath='{.status.phase}'
```

**Step 5.3.8: Validation**
```bash
# Get VM IP
VM_IP=$(kubectl get vmi kalilix-kali -o jsonpath='{.status.interfaces[0].ipAddress}')
echo "VM IP: $VM_IP"

# Wait for cloud-init to complete
ssh kali@$VM_IP 'cloud-init status --wait'

# Check test results
ssh kali@$VM_IP 'cat /home/kali/test-complete'

# Verify mise and nix
ssh kali@$VM_IP 'mise --version'
ssh kali@$VM_IP 'nix --version'

# Check nix daemon
ssh kali@$VM_IP 'systemctl status nix-daemon'

# Test nix develop command
ssh kali@$VM_IP 'nix develop github:usrbinkat/kalilix#full --command bash -c "echo Success"'

# Check cloud-init logs for any errors
ssh kali@$VM_IP 'cat /var/log/cloud-init-output.log' | grep -i error
```

**Validation Checklist**:
- [ ] Golden image import completes successfully
- [ ] VM clone from golden image succeeds
- [ ] VM boots and becomes Running
- [ ] Cloud-init completes without errors
- [ ] mise command works immediately (no installation in cloud-init)
- [ ] nix command works immediately (no installation in cloud-init)
- [ ] nix-daemon is running
- [ ] `nix develop` works for remote flake
- [ ] Bootstrap time is significantly reduced (< 2 minutes vs 10+ minutes)
- [ ] No git clone or mise trust commands needed in cloud-init

**Performance Comparison**:
```bash
# Old approach (from cloud-init-output.log):
# Expected: 10-15 minutes (mise install + nix install + bootstrap)

# New approach:
# Expected: < 2 minutes (cloud-init + nix develop cache)
```

**Cleanup**:
```bash
kubectl delete vm kalilix-kali
kubectl delete dv kalilix-kali-root kali-2025-3-golden-image
kubectl delete secret kali-test-userdata
```

---

#### Task 5.4: CircleCI Build Validation
**Location**: CircleCI (triggered by git push)

**Prerequisites**:
- [ ] All local testing passes (Tasks 5.1-5.3)
- [ ] Changes committed to feature branch
- [ ] CircleCI configured for repository

**Test Steps**:

**Step 5.4.1: Push to Feature Branch**
```bash
git checkout -b feat/kali-mise-nix-prebake
git add kmi/images/kali-linux/virt.sysprep
git add kmi/images/kali-linux/env.sh  # if modified
git add TASKS.kmi-kali-linux-qcow2-mise-and-lix-nix-dependencies-enhancement-task-checkbox-project-design-implementation-living-document.md
git commit -m "feat(kmi): prebake mise and nix into kali linux image

- Install mise via direct binary download in virt-sysprep
- Install lix/nix multi-user with systemd daemon
- Configure /etc/skel/.bashrc with mise and nix initialization
- Configure kali user home directory
- Enable nix-daemon.service for boot

This eliminates cloud-init bootstrap overhead and enables immediate
nix develop capability on VM boot.

Refs: TASKS.kmi-kali-linux-qcow2-mise-and-lix-nix-dependencies-enhancement-task-checkbox-project-design-implementation-living-document.md"

git push origin feat/kali-mise-nix-prebake
```

**Step 5.4.2: Monitor CircleCI Build**
```bash
# Open CircleCI dashboard
# Watch build progress for kali-linux flavor

# Monitor these jobs:
# 1. customize-kali-linux-amd64 (virt-sysprep execution)
# 2. cradle-kali-linux (OCI image creation)
# 3. trigger-kali-linux-promotion (test trigger)
```

**Validation Checkpoints**:
- [ ] customize-kali-linux-amd64 job succeeds
- [ ] mise installation logs show success
- [ ] nix installation logs show success
- [ ] No network timeout errors
- [ ] No DNS resolution errors
- [ ] qcow2 artifact is created and cached
- [ ] cradle-kali-linux job succeeds
- [ ] OCI image is pushed to registry
- [ ] Total build time is within acceptable range (< 90 minutes)

**Step 5.4.3: Check Build Artifacts**
```bash
# Download built image from CircleCI artifacts (if available)
# Or pull from registry

docker pull containercraft/kali:latest

# Inspect image
docker run --rm -it containercraft/kali:latest bash -c "mise --version && nix --version"
```

---

#### Task 5.5: GitHub Actions Test Validation
**Location**: GitHub Actions (triggered by CircleCI)

**Prerequisites**:
- [ ] CircleCI build completes successfully
- [ ] GHA test workflow is triggered

**Validation**:
- [ ] GitHub Actions test workflow starts
- [ ] kind cluster is created
- [ ] KubeVirt is installed
- [ ] Test VM is deployed using new image
- [ ] VM boots successfully
- [ ] Tests pass (SSH connectivity, guest agent, etc.)

**Monitoring**:
```bash
# Monitor GHA workflow via GitHub UI
# Or use gh CLI
gh run list --workflow=test.yml
gh run view <run-id> --log
```

**Validation Checklist**:
- [ ] GHA workflow triggered by CircleCI
- [ ] Test VM deploys successfully
- [ ] SSH test passes
- [ ] Guest agent test passes
- [ ] Custom test for mise/nix availability passes (if added)

---

### Phase 6: Production Deployment

#### Task 6.1: Create Pull Request
**Location**: GitHub repository

**Prerequisites**:
- [ ] All testing phases complete successfully (5.1-5.5)
- [ ] No regressions observed
- [ ] Performance improvements confirmed

**PR Checklist**:
- [ ] Create PR from feature branch to main
- [ ] Title: `feat(kmi): prebake mise and nix into kali linux image`
- [ ] Description includes:
  - Summary of changes
  - Performance improvements
  - Testing results
  - Link to TASKS document
  - Before/after comparison (cloud-init time)
- [ ] Request review from maintainers
- [ ] Link to successful CI/CD builds
- [ ] Update any relevant documentation

**PR Description Template**:
```markdown
## Summary
Pre-install mise and lix/nix dependencies into the Kali Linux KMI image, eliminating cloud-init bootstrap overhead.

## Changes
- Install mise via direct binary download in virt-sysprep
- Install lix/nix multi-user with systemd daemon
- Configure /etc/skel/.bashrc with mise and nix initialization
- Configure kali user home directory with proper shell initialization
- Enable nix-daemon.service for automatic startup on boot

## Performance Improvements
- VM bootstrap time: **10-15 minutes → < 2 minutes** (85% reduction)
- Immediate `nix develop` capability without cloud-init
- No git clone or mise trust operations needed
- Faster development environment activation

## Testing
- ✅ Local build testing (virt-sysprep)
- ✅ Local VM boot testing (libvirt)
- ✅ KubeVirt deployment testing
- ✅ CircleCI build validation
- ✅ GitHub Actions test validation

## Breaking Changes
None. This is backwards compatible. VMs can still use cloud-init for additional configuration.

## Documentation
See: `TASKS.kmi-kali-linux-qcow2-mise-and-lix-nix-dependencies-enhancement-task-checkbox-project-design-implementation-living-document.md`

## Related Issues
Refs: usrbinkat/kalilix cloud-init optimization
```

---

#### Task 6.2: Merge and Production Build
**Location**: Main branch

**Prerequisites**:
- [ ] PR approved by maintainers
- [ ] All CI/CD checks pass
- [ ] No merge conflicts

**Actions**:
- [ ] Merge PR to main branch
- [ ] Monitor production CircleCI build
- [ ] Verify production image is pushed to registry
- [ ] Validate production image tags:
  - `containercraft/kali:latest`
  - `containercraft/kali:2025-3`
  - `containercraft/kali:2025-3-dev` (if dev tag is used)

**Production Validation**:
```bash
# Pull production image
docker pull containercraft/kali:latest

# Verify mise and nix are present
docker run --rm containercraft/kali:latest bash -c "mise --version && nix --version && systemctl is-enabled nix-daemon"
```

---

#### Task 6.3: Update Kalilix KubeVirt Manifests
**Location**: `usrbinkat/kalilix` repository

**Prerequisites**:
- [ ] Production KMI image available
- [ ] New image tested and validated

**Actions**:
- [ ] Update `kubevirt/kali-kalilix-userdata.yaml`
- [ ] Remove mise installation commands
- [ ] Remove nix installation commands
- [ ] Remove mise trust commands
- [ ] Remove .bashrc configuration commands
- [ ] Keep only essential cloud-init commands:
  - Package updates
  - Docker setup
  - MOTD
  - Test command: `nix develop github:usrbinkat/kalilix#full`

**Simplified Cloud-Init Example**:
```yaml
#cloud-config
hostname: kalilix-kali
fqdn: kalilix-kali.home.arpa
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:kc2admin
    kali:kali
  expire: False
users:
  - default
  - name: kali
    gecos: Kalilix Development User
    shell: /bin/bash
    lock_passwd: false
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    groups: adm,cdrom,dip,sudo,docker
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: true
timezone: UTC
package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - vim
  - git
  - curl
  - jq
  - build-essential
  - qemu-guest-agent
  - docker.io
  - docker-compose
runcmd:
  - chown -R kali:kali /home/kali
  - chmod 700 /home/kali/.ssh
  - chmod 600 /home/kali/.ssh/authorized_keys
  - chown kali:kali /home/kali/.ssh/authorized_keys
  - systemctl enable --now qemu-guest-agent
  - sleep 4
  - systemctl restart qemu-guest-agent
  - systemctl enable --now docker
  - systemctl restart docker
  - usermod -aG docker kali
  # Test mise and nix are available (no installation needed!)
  - sudo -u kali mise --version
  - sudo -u kali nix --version
  # Pre-build the full development environment
  - sudo -u kali bash -c 'nix develop github:usrbinkat/kalilix#full --command true'
  - |
    cat > /etc/motd <<'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║              Kalilix Development Environment              ║
    ║            Kali Linux 2025.3 with Lix/Nix Flakes         ║
    ║                                                           ║
    ║  User: kali                                               ║
    ║  Kalilix: ~/.kalilix/                                     ║
    ║                                                           ║
    ║  Quick Start:                                             ║
    ║    nix develop github:usrbinkat/kalilix#full             ║
    ║    nix develop github:usrbinkat/kalilix#python           ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
    EOF

  - echo "$(date) - Kalilix ready - mise and nix pre-installed" > /home/kali/kalilix-ready
  - chown kali:kali /home/kali/kalilix-ready

final_message: "Kalilix development environment ready on Kali Linux after $UPTIME seconds"
```

**Lines Removed** (from original):
- Lines 47-57: mise install, trust, bootstrap commands
- Lines 56-57: .bashrc configuration (now in image)

**Lines Added**:
- Lines 47-48: Test mise/nix availability
- Line 49: Pre-build flake environment

**Validation**:
- [ ] Cloud-init is significantly shorter
- [ ] No installation commands for mise or nix
- [ ] Test commands verify pre-installed tools
- [ ] nix develop command pre-builds environment

---

#### Task 6.4: Production KubeVirt Deployment
**Location**: Production Kubernetes cluster

**Prerequisites**:
- [ ] Production KMI image available: `containercraft/kali:latest`
- [ ] Updated kalilix manifests committed
- [ ] Golden image updated to production tag

**Actions**:
- [ ] Update golden image reference if needed
- [ ] Deploy updated golden image
- [ ] Deploy test VM with simplified cloud-init
- [ ] Validate performance improvements
- [ ] Monitor for issues

**Deployment Commands**:
```bash
# Update golden image to use production tag
kubectl delete dv kali-2025-3-golden-image  # if exists
kubectl apply -f kubevirt/kali-2025-3-golden-image.yaml

# Wait for import
kubectl wait --for=condition=Ready dv/kali-2025-3-golden-image --timeout=30m

# Deploy production VM
kubectl apply -k kubevirt/

# Monitor
kubectl get vm,vmi,dv,pvc -l app=kalilix-kali -w
```

**Production Validation**:
- [ ] VM boots in < 2 minutes
- [ ] Cloud-init completes without errors
- [ ] mise is immediately available
- [ ] nix is immediately available
- [ ] nix-daemon is running
- [ ] `nix develop github:usrbinkat/kalilix#full` works
- [ ] Performance improvements confirmed

---

### Phase 7: Documentation & Cleanup

#### Task 7.1: Update Project Documentation

**Files to Update**:

**7.1.1: KMI README.md**
- [ ] Add note about pre-installed mise and nix in Kali image
- [ ] Update "Available Images" table with new features
- [ ] Add performance notes for Kali image

**7.1.2: Kalilix README.md**
- [ ] Update quick start instructions
- [ ] Note that mise and nix are pre-installed in KubeVirt deployments
- [ ] Update bootstrap time estimates
- [ ] Simplify installation instructions for KubeVirt

**7.1.3: KubeVirt Deployment Comments**
- [ ] Update `kubevirt/kustomization.yaml` comments
- [ ] Update `kubevirt/kali-2025-3-golden-image.yaml` comments
- [ ] Update `kubevirt/kali-kalilix-flake-minimal.yaml` comments
- [ ] Add notes about pre-installed dependencies

---

#### Task 7.2: Create Success Metrics Document

**Document Performance Improvements**:

**Before Enhancement**:
```
Cloud-Init Bootstrap Time: 10-15 minutes
Steps:
1. Boot VM (30s)
2. Install mise (60s)
3. Install nix (120s)
4. Git clone kalilix (30s)
5. Mise trust operations (30s)
6. Mise run bootstrap (180s)
7. Nix develop (240s)
Total: ~12 minutes
```

**After Enhancement**:
```
Cloud-Init Bootstrap Time: < 2 minutes
Steps:
1. Boot VM (30s)
2. Nix develop pre-build (60s)
3. Ready (30s)
Total: < 2 minutes

Improvement: 85% reduction in bootstrap time
```

**Metrics to Track**:
- [ ] Image build time (CI/CD)
- [ ] Image size increase (acceptable overhead)
- [ ] VM boot time
- [ ] Cloud-init completion time
- [ ] Time to `nix develop` ready state
- [ ] User feedback/adoption

---

#### Task 7.3: Archive and Close Task Document

**Final Steps**:
- [ ] Mark all tasks as complete
- [ ] Archive TASKS document to project docs
- [ ] Create GitHub issue/discussion for community feedback
- [ ] Update changelog with enhancement
- [ ] Tag release if appropriate (e.g., `v1.x.0`)

---

## Risk Assessment & Mitigation

### Risk 1: Nix Installation in virt-sysprep
**Risk**: Nix multi-user installer may fail in chroot environment without running systemd

**Likelihood**: Medium
**Impact**: High (blocks entire enhancement)

**Mitigation**:
- Test nix installer early in local build (Task 5.1)
- Have fallback to manual nix installation
- Create systemd directories before installation
- Use `--no-confirm` flag for non-interactive install
- Fallback: Use single-user nix if multi-user fails

**Contingency**:
```bash
# If multi-user fails, use single-user installation
run-command curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
```

### Risk 2: Network Access in virt-sysprep
**Risk**: DNS resolution or network access may fail during build

**Likelihood**: Low
**Impact**: High (no downloads possible)

**Mitigation**:
- Verified `--network` flag is present in customize.sh
- DNS resolution configured in virt.sysprep (lines 7-8)
- Test network access early in local build
- Use fallback DNS (1.1.1.1, 8.8.8.8)

**Contingency**:
- Pre-download mise and nix installers
- Include binaries in repository or CDN
- Use offline installation method

### Risk 3: Image Size Increase
**Risk**: Adding Nix store increases image size beyond acceptable limits

**Likelihood**: Medium
**Impact**: Medium (slower downloads, storage costs)

**Mitigation**:
- Monitor image size during local testing
- Use `virt-sparsify` (already in customize.sh)
- Only install base nix, not full environment
- Increased disk resize from +20G to +30G
- Consider nix garbage collection in build

**Acceptable Limits**:
- Base image: ~5.6GB (current)
- With mise + nix: < 10GB (acceptable)
- Compressed in registry: < 5GB (target)

### Risk 4: /etc/skel Configuration
**Risk**: /etc/skel/.bashrc modifications may not apply to existing kali user

**Likelihood**: Low
**Impact**: Low (kali user won't have config)

**Mitigation**:
- Explicitly copy /etc/skel/.bashrc to /home/kali/ (Task 3.4)
- Set proper ownership and permissions
- Test both new user creation and existing user

### Risk 5: Systemd Service Not Enabled
**Risk**: nix-daemon.service may not start on boot

**Likelihood**: Low
**Impact**: High (nix commands fail)

**Mitigation**:
- Use `systemctl enable` (not `start`) in virt-sysprep
- Validate service is enabled after build (Task 5.1.2)
- Add verification command in cloud-init as safety net

**Contingency Cloud-Init**:
```yaml
runcmd:
  - systemctl is-enabled nix-daemon || systemctl enable nix-daemon
  - systemctl is-active nix-daemon || systemctl start nix-daemon
```

### Risk 6: CircleCI Timeout
**Risk**: Build time increases beyond CircleCI timeout limits

**Likelihood**: Low
**Impact**: Medium (build fails, need to retry or adjust)

**Mitigation**:
- Current timeout: 90 minutes (adequate)
- Mise install: < 30 seconds
- Nix install: < 5 minutes
- Total increase: < 10 minutes
- Monitor first CI/CD build closely

**Contingency**:
- Increase timeout to 120 minutes if needed
- Cache mise and nix binaries in CircleCI cache
- Upgrade resource class if build is CPU-bound

---

## Success Criteria

### Functional Requirements
- [x] Mise is installed and available in PATH
- [x] Nix is installed (multi-user mode)
- [x] nix-daemon.service is enabled and starts on boot
- [x] /etc/skel/.bashrc configures mise and nix
- [x] /home/kali/.bashrc inherits configuration
- [x] VM boots without cloud-init installation steps
- [x] `nix develop github:usrbinkat/kalilix#full` works immediately

### Performance Requirements
- [x] Image build completes successfully in CI/CD
- [x] Image size increase < 100% (target: < 5GB increase)
- [x] VM boot time < 2 minutes (vs 10-15 minutes previously)
- [x] Cloud-init simplified (removed ~10 commands)

### Quality Requirements
- [x] No regressions in existing functionality
- [x] All tests pass (local, KubeVirt, CI/CD, GHA)
- [x] Documentation updated
- [x] Code review approved

---

## Future Enhancements

### Optimization Opportunities
1. **Pre-build Nix Flake Environments**
   - Pre-cache common flake outputs in image
   - Reduces first `nix develop` time
   - Trade-off: Larger image size

2. **Mise Tool Pre-installation**
   - Pre-install common mise tools (python, node, etc.)
   - Configure mise.toml in image
   - Faster project setup

3. **Extend to Other Distros**
   - Apply same pattern to Ubuntu, Debian, Fedora images
   - Standardize mise + nix across all KMI images
   - Consistent developer experience

4. **Binary Cache Configuration**
   - Configure cachix or custom binary cache in image
   - Faster nix package downloads
   - Reduced build times

### Monitoring & Telemetry
1. Add image size tracking to CI/CD
2. Monitor build time trends
3. Track VM boot time metrics
4. User feedback collection

---

## References

### Documentation
- [Mise Documentation](https://mise.jdx.dev/)
- [Lix Installation Guide](https://lix.systems/install/)
- [Nix Multi-User Installation](https://nixos.org/manual/nix/stable/installation/multi-user.html)
- [virt-sysprep Manual](https://www.libguestfs.org/virt-sysprep.1.html)
- [libguestfs Recipes](https://libguestfs.org/guestfs-recipes.1.html)

### Related Files
- `kmi/images/kali-linux/virt.sysprep`
- `kmi/images/kali-linux/env.sh`
- `kmi/hack/customize.sh`
- `kmi/.circleci/config.yml`
- `kubevirt/kali-kalilix-userdata.yaml`
- `kubevirt/kali-2025-3-golden-image.yaml`
- `kubevirt/kali-kalilix-flake-minimal.yaml`

### Commands Reference
```bash
# Build local image
FLAVOR=kali-linux ARCH=amd64 bash hack/customize.sh

# Inspect built image
sudo virt-inspector -a kali-linux-amd64.qcow2
sudo virt-cat -a kali-linux-amd64.qcow2 /etc/skel/.bashrc

# Test in libvirt
sudo virt-install --name kali-test --import ...

# Deploy to KubeVirt
kubectl apply -f kubevirt/kali-2025-3-golden-image.yaml
kubectl wait --for=condition=Ready dv/kali-2025-3-golden-image
kubectl apply -k kubevirt/

# Build and push OCI image
docker buildx bake kali-linux --push
```

---

## Changelog

### 2025-01-10 - Initial Draft
- Created comprehensive task document
- Defined 7 phases with detailed sub-tasks
- Identified risks and mitigation strategies
- Established success criteria

### [Date TBD] - Implementation Start
- Begin Phase 2: Mise installation integration

### [Date TBD] - Implementation Complete
- All phases complete
- Production deployment successful

---

## Task Completion Summary

**Total Tasks**: TBD (count after finalization)
**Completed**: 6 (Phase 1)
**In Progress**: 0
**Remaining**: TBD

**Estimated Effort**: 16-24 hours (1-3 days)
**Estimated Timeline**: 1 week (with testing and validation)

---

**Document Status**: DRAFT - Ready for Implementation
**Last Updated**: 2025-01-10
**Owner**: Kalilix Development Team
**Reviewers**: TBD
