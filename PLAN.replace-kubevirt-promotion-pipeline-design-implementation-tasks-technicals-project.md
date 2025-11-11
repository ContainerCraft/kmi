# PLAN: Replace KubeVirt Promotion Pipeline with KVM/libvirt Direct Testing

**Status:** Draft
**Created:** 2025-11-11
**Owner:** Kalilix KMI Team
**Target Completion:** 4 weeks

---

## Executive Summary

Replace the current KubeVirt-in-kind testing approach with direct KVM/libvirt testing using cloud-init ISOs. This eliminates nested virtualization overhead, reduces test execution time from 15-20 minutes to 3-5 minutes per flavor, simplifies the pipeline architecture, and provides more reliable validation of VM boot behavior.

**Current State:** CircleCI builds images → packages as OCI containers → triggers GitHub Actions → kind cluster → KubeVirt (emulated) → 3 basic tests
**Target State:** CircleCI builds images → packages as OCI containers → triggers GitHub Actions → KVM direct → comprehensive boot validation

**Key Benefits:**
- **5-10x faster tests:** 3-5 minutes vs 15-20 minutes per flavor
- **Native KVM acceleration:** No software emulation overhead
- **90% reduction in complexity:** 2 components vs 7 (kind, kubectl, KubeVirt, virtctl, CNI, operator, CRDs)
- **Better test coverage:** Validates actual boot performance, cloud-init completion, disk growth
- **Easier debugging:** Direct console access vs multi-layer log aggregation
- **Cost reduction:** Lower CI runner time, reduced resource usage (2-3GB vs 6-8GB RAM)

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Problem Statement](#problem-statement)
3. [Proposed Architecture](#proposed-architecture)
4. [Technical Design](#technical-design)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Migration Plan](#migration-plan)
8. [Risk Assessment](#risk-assessment)
9. [Success Metrics](#success-metrics)
10. [Timeline](#timeline)

---

## Current State Analysis

### Pipeline Overview

**Phase 1: CircleCI Build (Per-Distribution, Per-Architecture)**

```
customize job → hack/customize.sh
├── Download qcow2 from upstream mirror
├── Verify checksums (SHA256/SHA512)
├── Resize disk +30GB (for Nix store)
├── virt-sysprep customization (libguestfs)
│   ├── Install packages (cloud-init, qemu-guest-agent, openssh-server)
│   ├── Enable services (systemctl enable)
│   ├── Configure DNS (fix libguestfs DNS issues)
│   └── Distribution-specific setup (Mise, Lix/Nix for Kali)
├── Sparsify (compress unused space)
└── Cache qcow2 artifact

cradle job → docker buildx bake
├── Attach workspace (amd64 + arm64 qcow2)
├── Build multi-arch OCI container (Containerfile)
│   ├── FROM ubi8/ubi-minimal
│   ├── COPY images/${FLAVOR}/ → /meta/
│   └── COPY ${FLAVOR}-${ARCH}.qcow2 → /disk/${FLAVOR}.qcow2
└── Push to docker.io/containercraft/${FLAVOR}:${VERSION}-dev

trigger-tests job
└── POST to GitHub Actions API (.github/workflows/test.yml)
```

**Phase 2: GitHub Actions Test (kind + KubeVirt)**

```
test job → bats tests/run.bats
├── Create kind cluster (2 nodes: control-plane + worker)
├── Install virtctl CLI (KubeVirt v0.52.0)
├── Deploy KubeVirt operator + CR
│   └── Patch: useEmulation=true (no KVM, use TCG)
├── Wait for KubeVirt components (infinite loop potential)
│   ├── virt-operator
│   ├── virt-api
│   ├── virt-controller
│   └── virt-handler
├── Create SSH keypair + secret
├── Apply VM resources
│   ├── ssh-service.yaml (NodePort 30950)
│   ├── vm-presets.yaml (4GB RAM, 1 CPU)
│   └── vmi.yaml (VirtualMachineInstance)
├── Run tests (BATS)
│   ├── Test 1: VM pod ready (retry 5x, timeout 240s)
│   ├── Test 2: qemu-guest-agent (retry 120x, timeout 600s)
│   └── Test 3: SSH connectivity (retry 90x, timeout 450s)
└── Teardown (collect logs, delete VMI, delete cluster)

promote job → skopeo + cosign
├── Copy: ${FLAVOR}:${VERSION}-dev → ${FLAVOR}:${VERSION}
├── Sign with cosign (keyless, OIDC)
└── Verify signature (retry 3x)
```

### Current Pain Points

#### 1. **Nested Virtualization: TCG Emulation Overhead**

**Issue:** KubeVirt runs inside Docker containers (kind nodes), requiring software emulation (`useEmulation=true`) because nested KVM is unreliable.

**Impact:**
- TCG emulation is 10-100x slower than native KVM
- Boot times: 5-10 minutes vs 30-60 seconds
- Timing flakiness causes intermittent test failures
- Resource intensive: 4GB RAM per VM + KubeVirt overhead + kind overhead

**Evidence:** `tests/run.bats:45-46`
```bash
kubectl patch -n kubevirt kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

#### 2. **Excessive Retry Logic = Unreliable Tests**

**Issue:** Tests rely on aggressive retries to mask flakiness.

**Examples:**
- qemu-guest-agent test: **120 retries × 5s = 10 minutes timeout**
- SSH connectivity test: **90 retries × 5s = 7.5 minutes timeout**
- KubeVirt component wait: **Infinite loop** with TODO comment warning

**Impact:**
- Tests take 15-20 minutes per flavor (mostly waiting)
- False positives (tests pass but VM is actually slow/broken)
- Hard to debug (logs buried in retry noise)
- CI runner cost accumulation

**Evidence:** `tests/run.bats:49`
```bash
# TODO: We can get stuck in an infinite loop here very easily
until kubectl wait --for condition=ready pod -n kubevirt --timeout=100s -l kubevirt.io=virt-operator; do sleep 1; done
```

#### 3. **Multi-Layer Complexity: 7 Components**

**Issue:** Pipeline spans 3 CI systems with different tooling.

**Components:**
1. **CircleCI:** Image building, caching, workspace persistence
2. **GitHub Actions:** Testing orchestration (triggered via API)
3. **kind:** Kubernetes cluster in Docker (2 nodes)
4. **KubeVirt:** VM orchestration layer (operator, controller, handler)
5. **Docker buildx:** Multi-arch container builds
6. **BATS:** Shell-based testing framework
7. **virtctl:** KubeVirt CLI tool

**Impact:**
- Hard to reproduce locally (need CircleCI runner environment)
- Debugging requires access to CircleCI, GHA, Docker Hub
- Secrets management across platforms (DOCKERHUB_*, GITHUB_ACTIONS_PAT)
- Dependency on external GitHub Action (helm/kind-action@v1.3.0)

#### 4. **Network Port Forwarding: 4-Layer Stack**

**Issue:** SSH test connects through multiple network layers:

```
host:30950 → kind node:30950 → Kubernetes NodePort:30950 → VMI pod:22
```

**Impact:**
- Port conflicts on shared GitHub Actions runners
- Network flakiness (CNI, iptables, Docker NAT)
- Hard to debug connection failures (which layer failed?)
- Cannot test multiple VMs concurrently (port collision)

**Evidence:** `.github/workflows/kind/config.yml:14-16`
```yaml
extraPortMappings:
- containerPort: 30950
  hostPort: 30950
```

#### 5. **Outdated KubeVirt Version (v0.52.0 from 2022)**

**Issue:** Hardcoded old version, 2+ years behind current.

**Impact:**
- Missing bug fixes and features
- Potential security vulnerabilities
- Compatibility issues with newer Kubernetes versions
- No access to improvements in newer releases

**Evidence:** `tests/run.bats:14`
```bash
KUBEVIRT_VERSION="v0.52.0"  # Released: 2022
```

#### 6. **Test Coverage Gaps**

**Current tests only validate:**
1. Pod becomes ready (scheduler works)
2. qemu-guest-agent starts (basic boot validation)
3. SSH connects once (network + cloud-init user creation)

**Not tested:**
- Cloud-init completion status
- Disk resizing (growpart functionality)
- Package installations verification
- Service enablement verification
- Multi-boot scenarios
- Performance characteristics
- Memory pressure handling
- Graceful shutdown/reboot

---

## Problem Statement

The current KubeVirt-in-kind testing approach was designed to validate Kubernetes integration but adds unnecessary complexity for validating VM disk images. The project's goal is to produce **production-ready VM disk images** that boot reliably with cloud-init, not to validate KubeVirt orchestration.

**Core Problem:** Testing KubeVirt integration when we should be testing VM boot quality.

**Consequences:**
- Slow feedback loop (15-20 minutes per test)
- High CI costs (excessive runner time)
- Low developer productivity (hard to reproduce locally)
- False confidence (tests pass but VM may have issues)
- Maintenance burden (7 components to keep updated)

**Desired Outcome:**
- Fast, reliable tests that validate actual VM boot behavior
- Simple, reproducible local testing
- Minimal dependencies
- Clear failure modes
- Comprehensive validation of image customizations

---

## Proposed Architecture

### High-Level Design

Replace KubeVirt-in-kind with **direct KVM/libvirt testing** using cloud-init ISO generation.

```
┌─────────────────────────────────────────────────────────────────┐
│ GHA: test Job (ubuntu-22.04 runner with KVM enabled)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Enable KVM on runner                                       │
│     ├── Check /dev/kvm exists                                  │
│     └── Install: qemu-kvm, cloud-utils, socat                  │
│                                                                 │
│  2. Extract qcow2 from dev container                           │
│     ├── podman pull docker.io/containercraft/${FLAVOR}-dev     │
│     ├── podman create --name tmp ${IMAGE}                      │
│     ├── podman cp tmp:/disk/${FLAVOR}.qcow2 ./test.qcow2       │
│     └── podman rm tmp                                          │
│                                                                 │
│  3. Generate cloud-init ISO (generate-cloudinit-iso.sh)        │
│     ├── Create meta-data (instance-id, local-hostname)         │
│     ├── Create user-data (SSH key, test user, minimal config)  │
│     └── Run: cloud-localds seed.iso user-data meta-data        │
│                                                                 │
│  4. Launch VM with KVM (launch-vm.sh)                          │
│     └── qemu-system-x86_64 -enable-kvm -cpu host -m 2048 ...  │
│         ├── Drive: test.qcow2 (virtio)                         │
│         ├── Drive: seed.iso (cloud-init)                       │
│         ├── Net: user mode, hostfwd=tcp::2222-:22              │
│         ├── qemu-guest-agent: socket /tmp/qga.sock             │
│         └── Daemonize with PID file                            │
│                                                                 │
│  5. Run tests (test-vm.sh)                                     │
│     ├── Test 1: qemu-guest-agent responds (60 retries × 2s)    │
│     ├── Test 2: SSH connectivity (30 retries × 2s)             │
│     ├── Test 3: cloud-init completion (cloud-init status)      │
│     ├── Test 4: disk growth (df -h /)                          │
│     ├── Test 5: package installations (distribution-specific)  │
│     └── Test 6: service status (qemu-guest-agent, sshd)        │
│                                                                 │
│  6. Cleanup                                                    │
│     ├── kill $(cat /tmp/vm.pid)                                │
│     └── rm test.qcow2 seed.iso /tmp/qga.sock /tmp/vm.pid       │
│                                                                 │
│  7. If tests pass → proceed to promote job                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Architecture Comparison

| Aspect | **KubeVirt-in-kind (Current)** | **KVM/libvirt Direct (Proposed)** |
|--------|--------------------------------|-----------------------------------|
| **Virtualization** | Software emulation (TCG) | Hardware acceleration (KVM) |
| **Boot time** | 5-10 minutes | 30-60 seconds |
| **Test runtime** | 15-20 minutes | 3-5 minutes |
| **Setup time** | 7 minutes (cluster + KubeVirt) | 30 seconds (install packages) |
| **Components** | 7 (kind, kubectl, KubeVirt, virtctl, CNI, operator, CRDs) | 2 (qemu-kvm, cloud-utils) |
| **Network stack** | 4 layers (Docker NAT → kind → K8s Service → VMI) | 1 layer (QEMU user networking) |
| **Debugging** | Multi-layer logs (kind, KubeVirt, operator, VMI) | Single process, direct console |
| **Flakiness** | High (timing, CNI, nested virt) | Low (direct KVM, no orchestration) |
| **Resource usage** | 6-8GB RAM | 2-3GB RAM |
| **Port conflicts** | Yes (NodePort 30950) | No (dynamic allocation) |
| **Local reproduction** | Hard (requires kind cluster) | Easy (single qemu command) |
| **Test coverage** | Kubernetes integration | Actual VM boot behavior |
| **CI runner cost** | High (15-20 min/flavor) | Low (3-5 min/flavor) |

### Key Technical Decisions

#### 1. **Use GitHub Actions Native KVM Support**

GitHub Actions ubuntu-22.04 runners have KVM enabled by default. We just need to configure udev rules.

**Rationale:**
- No external dependencies (kind-action)
- Native hardware acceleration
- Proven reliability

**Implementation:**
```bash
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
```

#### 2. **Use cloud-localds for Cloud-Init ISO Generation**

Part of `cloud-image-utils` package, standard tool for cloud-init testing.

**Rationale:**
- Industry standard (used by Ubuntu, Debian, etc.)
- Simple API: `cloud-localds output.iso user-data meta-data`
- NoCloud datasource (works offline, no network dependencies)

#### 3. **Use QEMU User Networking (SLIRP)**

No need for bridge networking, TAP devices, or iptables rules.

**Rationale:**
- Simplest networking mode
- No root permissions required
- Port forwarding built-in: `hostfwd=tcp::2222-:22`
- Isolated from host network (no conflicts)

#### 4. **Use UNIX Socket for qemu-guest-agent Communication**

Direct socket communication, no virtctl CLI needed.

**Rationale:**
- JSON-RPC over UNIX socket (standard protocol)
- Simple testing: `echo '{"execute":"guest-ping"}' | socat - UNIX:/tmp/qga.sock`
- No additional tooling dependencies

#### 5. **Keep CircleCI Build Pipeline Unchanged**

Only modify GitHub Actions testing phase.

**Rationale:**
- CircleCI build works well (caching, multi-arch, workspace)
- Minimize scope of change
- Reduce migration risk
- Easier rollback if needed

---

## Technical Design

### Component 1: Cloud-Init ISO Generator

**File:** `tests/generate-cloudinit-iso.sh`

**Purpose:** Generate NoCloud datasource ISO with test configuration.

**Inputs:**
- `$FLAVOR`: Distribution name (e.g., ubuntu-24-04)
- `$SSH_KEY_PATH`: Path to public key (default: ~/.ssh/id_rsa.pub)
- `$OUTPUT_ISO`: Output filename (default: seed.iso)

**Outputs:**
- `seed.iso`: Cloud-init configuration ISO

**Implementation:**

```bash
#!/bin/bash
set -euo pipefail

FLAVOR=${1:-ubuntu-24-04}
SSH_KEY_PATH=${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}
OUTPUT_ISO=${OUTPUT_ISO:-seed.iso}

# Validate inputs
if [[ ! -f "${SSH_KEY_PATH}" ]]; then
  echo "Error: SSH public key not found at ${SSH_KEY_PATH}"
  exit 1
fi

# Generate unique instance ID
INSTANCE_ID="test-${FLAVOR}-$(date +%s)"

# Create meta-data (minimal required fields)
cat > meta-data <<EOF
instance-id: ${INSTANCE_ID}
local-hostname: ${FLAVOR}
EOF

# Create user-data (test configuration)
cat > user-data <<EOF
#cloud-config
hostname: ${FLAVOR}

# Create test user with SSH key
users:
  - name: testuser
    ssh_authorized_keys:
      - $(cat "${SSH_KEY_PATH}")
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false

# Enable SSH password auth for debugging
ssh_pwauth: true
disable_root: false

# Minimal package management (speed over completeness)
package_update: false
package_upgrade: false

# Enable required services
runcmd:
  - systemctl enable qemu-guest-agent || true
  - systemctl start qemu-guest-agent || true
  - systemctl restart sshd || true

# Grow partition to use full disk
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false

# Expand filesystem after partition growth
resize_rootfs: true

# Report completion
final_message: "Cloud-init completed in \$UPTIME seconds"
EOF

# Generate ISO using cloud-localds
cloud-localds "${OUTPUT_ISO}" user-data meta-data

echo "✓ Cloud-init ISO generated: ${OUTPUT_ISO}"
echo "  Instance ID: ${INSTANCE_ID}"
echo "  Hostname: ${FLAVOR}"
echo "  SSH user: testuser"

# Cleanup intermediate files
rm -f meta-data user-data

exit 0
```

**Testing:**
```bash
./generate-cloudinit-iso.sh ubuntu-24-04
file seed.iso  # Should show: ISO 9660 filesystem
```

---

### Component 2: VM Launcher

**File:** `tests/launch-vm.sh`

**Purpose:** Launch QEMU VM with KVM acceleration and cloud-init.

**Inputs:**
- `$1`: Path to qcow2 disk image
- `$2`: Path to cloud-init ISO
- `$SSH_PORT`: SSH port on host (default: 2222)
- `$QGA_SOCKET`: qemu-guest-agent socket path (default: /tmp/qga.sock)
- `$VM_PID_FILE`: PID file location (default: /tmp/vm.pid)
- `$VM_MEMORY`: RAM in MB (default: 2048)
- `$VM_CPUS`: CPU count (default: 2)

**Outputs:**
- VM running in background
- PID file created
- qemu-guest-agent socket created

**Implementation:**

```bash
#!/bin/bash
set -euo pipefail

QCOW2_FILE=${1:?Error: QCOW2 file path required}
CLOUD_INIT_ISO=${2:?Error: Cloud-init ISO path required}

# Validate inputs
if [[ ! -f "${QCOW2_FILE}" ]]; then
  echo "Error: QCOW2 file not found: ${QCOW2_FILE}"
  exit 1
fi

if [[ ! -f "${CLOUD_INIT_ISO}" ]]; then
  echo "Error: Cloud-init ISO not found: ${CLOUD_INIT_ISO}"
  exit 1
fi

# Configuration
SSH_PORT=${SSH_PORT:-2222}
QGA_SOCKET=${QGA_SOCKET:-/tmp/qga.sock}
VM_PID_FILE=${VM_PID_FILE:-/tmp/vm.pid}
VM_MEMORY=${VM_MEMORY:-2048}
VM_CPUS=${VM_CPUS:-2}
SERIAL_LOG=${SERIAL_LOG:-/tmp/vm-serial.log}

# Check KVM availability
if [[ ! -e /dev/kvm ]]; then
  echo "Warning: /dev/kvm not found, using TCG emulation (slower)"
  KVM_FLAGS=""
else
  echo "✓ KVM hardware acceleration available"
  KVM_FLAGS="-enable-kvm -cpu host"
fi

# Cleanup previous instances
if [[ -f "${VM_PID_FILE}" ]]; then
  OLD_PID=$(cat "${VM_PID_FILE}")
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "Killing previous VM instance (PID: ${OLD_PID})"
    kill "${OLD_PID}" || true
    sleep 2
  fi
  rm -f "${VM_PID_FILE}"
fi

rm -f "${QGA_SOCKET}"

# Launch QEMU
echo "Launching VM..."
echo "  QCOW2: ${QCOW2_FILE}"
echo "  Cloud-init: ${CLOUD_INIT_ISO}"
echo "  SSH port: localhost:${SSH_PORT}"
echo "  QGA socket: ${QGA_SOCKET}"
echo "  Memory: ${VM_MEMORY}MB"
echo "  CPUs: ${VM_CPUS}"

qemu-system-x86_64 \
  ${KVM_FLAGS} \
  -m ${VM_MEMORY} \
  -smp ${VM_CPUS} \
  -drive file="${QCOW2_FILE}",format=qcow2,if=virtio,cache=none \
  -drive file="${CLOUD_INIT_ISO}",format=raw,if=virtio,readonly=on \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-serial \
  -chardev socket,path="${QGA_SOCKET}",server=on,wait=off,id=qga0 \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -serial file:"${SERIAL_LOG}" \
  -display none \
  -daemonize \
  -pidfile "${VM_PID_FILE}"

# Wait for PID file creation
sleep 2

if [[ ! -f "${VM_PID_FILE}" ]]; then
  echo "Error: VM failed to start (no PID file created)"
  exit 1
fi

VM_PID=$(cat "${VM_PID_FILE}")

if ! kill -0 "${VM_PID}" 2>/dev/null; then
  echo "Error: VM process not running"
  cat "${SERIAL_LOG}"
  exit 1
fi

echo "✓ VM launched successfully (PID: ${VM_PID})"
echo "  Serial log: ${SERIAL_LOG}"

exit 0
```

**Testing:**
```bash
./launch-vm.sh test.qcow2 seed.iso
ps aux | grep qemu  # Should show running QEMU process
```

---

### Component 3: VM Test Suite

**File:** `tests/test-vm.sh`

**Purpose:** Execute comprehensive boot validation tests.

**Inputs:**
- `$FLAVOR`: Distribution name (for distribution-specific tests)
- `$SSH_PORT`: SSH port (default: 2222)
- `$QGA_SOCKET`: qemu-guest-agent socket (default: /tmp/qga.sock)
- `$VM_PID_FILE`: PID file (default: /tmp/vm.pid)

**Outputs:**
- Exit code 0: All tests passed
- Exit code 1: Test failure
- Test logs to stdout

**Implementation:**

```bash
#!/bin/bash
set -euo pipefail

FLAVOR=${FLAVOR:-ubuntu-24-04}
SSH_PORT=${SSH_PORT:-2222}
QGA_SOCKET=${QGA_SOCKET:-/tmp/qga.sock}
VM_PID_FILE=${VM_PID_FILE:-/tmp/vm.pid}
SSH_USER=${SSH_USER:-testuser}
SSH_KEY=${SSH_KEY:-${HOME}/.ssh/id_rsa}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

test_passed() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ PASS${NC}: $*"
}

test_failed() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗ FAIL${NC}: $*"
}

# Cleanup function
cleanup() {
  local exit_code=$?

  echo ""
  echo "═════════════════════════════════════════════════"
  echo "Test Summary"
  echo "═════════════════════════════════════════════════"
  echo "  Passed: ${TESTS_PASSED}"
  echo "  Failed: ${TESTS_FAILED}"
  echo "═════════════════════════════════════════════════"

  if [[ -f "${VM_PID_FILE}" ]]; then
    VM_PID=$(cat "${VM_PID_FILE}")
    log_info "Shutting down VM (PID: ${VM_PID})"
    kill "${VM_PID}" 2>/dev/null || true

    # Wait for graceful shutdown
    for i in {1..10}; do
      if ! kill -0 "${VM_PID}" 2>/dev/null; then
        log_info "VM shut down gracefully"
        break
      fi
      sleep 1
    done

    # Force kill if still running
    if kill -0 "${VM_PID}" 2>/dev/null; then
      log_warn "Forcing VM shutdown"
      kill -9 "${VM_PID}" 2>/dev/null || true
    fi
  fi

  exit ${exit_code}
}

trap cleanup EXIT

# Verify VM is running
if [[ ! -f "${VM_PID_FILE}" ]]; then
  log_error "VM PID file not found: ${VM_PID_FILE}"
  exit 1
fi

VM_PID=$(cat "${VM_PID_FILE}")
if ! kill -0 "${VM_PID}" 2>/dev/null; then
  log_error "VM process not running (PID: ${VM_PID})"
  exit 1
fi

log_info "Testing ${FLAVOR} VM (PID: ${VM_PID})"
echo ""

#############################################################################
# Test 1: QEMU Guest Agent Response
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: QEMU Guest Agent Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MAX_RETRIES=60
RETRY_DELAY=2
retry_count=0

log_info "Waiting for qemu-guest-agent (max ${MAX_RETRIES} attempts, ${RETRY_DELAY}s delay)..."

while [[ ${retry_count} -lt ${MAX_RETRIES} ]]; do
  if echo '{"execute":"guest-ping"}' | socat - UNIX-CONNECT:"${QGA_SOCKET}" 2>/dev/null | grep -q '"return"'; then
    test_passed "qemu-guest-agent responding after ${retry_count} attempts ($((retry_count * RETRY_DELAY))s)"
    break
  fi

  retry_count=$((retry_count + 1))

  if [[ ${retry_count} -eq ${MAX_RETRIES} ]]; then
    test_failed "qemu-guest-agent did not respond after ${MAX_RETRIES} attempts ($((MAX_RETRIES * RETRY_DELAY))s)"
    exit 1
  fi

  sleep ${RETRY_DELAY}
done

echo ""

#############################################################################
# Test 2: SSH Connectivity
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: SSH Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MAX_RETRIES=30
RETRY_DELAY=2
retry_count=0

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

log_info "Waiting for SSH (max ${MAX_RETRIES} attempts, ${RETRY_DELAY}s delay)..."

while [[ ${retry_count} -lt ${MAX_RETRIES} ]]; do
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" whoami 2>/dev/null | grep -q "${SSH_USER}"; then
    test_passed "SSH connectivity successful after ${retry_count} attempts ($((retry_count * RETRY_DELAY))s)"
    break
  fi

  retry_count=$((retry_count + 1))

  if [[ ${retry_count} -eq ${MAX_RETRIES} ]]; then
    test_failed "SSH did not respond after ${MAX_RETRIES} attempts ($((MAX_RETRIES * RETRY_DELAY))s)"
    exit 1
  fi

  sleep ${RETRY_DELAY}
done

echo ""

#############################################################################
# Test 3: Cloud-Init Completion
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Cloud-Init Completion Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Checking cloud-init status..."

if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
  "cloud-init status --wait --long" 2>&1; then
  test_passed "cloud-init completed successfully"
else
  test_failed "cloud-init did not complete or timed out"
  exit 1
fi

echo ""

#############################################################################
# Test 4: Disk Growth Verification
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Disk Growth Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Checking root filesystem size..."

DISK_INFO=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
  "df -h / | tail -1")

DISK_SIZE=$(echo "${DISK_INFO}" | awk '{print $2}')
DISK_USED=$(echo "${DISK_INFO}" | awk '{print $3}')
DISK_AVAIL=$(echo "${DISK_INFO}" | awk '{print $4}')
DISK_PERCENT=$(echo "${DISK_INFO}" | awk '{print $5}')

echo "  Size: ${DISK_SIZE}"
echo "  Used: ${DISK_USED}"
echo "  Available: ${DISK_AVAIL}"
echo "  Usage: ${DISK_PERCENT}"

# Verify disk is larger than 1GB (should be ~30GB after resize)
DISK_SIZE_GB=$(echo "${DISK_SIZE}" | sed 's/G.*//')
if [[ -n "${DISK_SIZE_GB}" ]] && [[ ${DISK_SIZE_GB%.*} -gt 1 ]]; then
  test_passed "disk growth successful (${DISK_SIZE})"
else
  test_failed "disk growth may have failed (size: ${DISK_SIZE})"
  exit 1
fi

echo ""

#############################################################################
# Test 5: Service Status Verification
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Service Status Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test qemu-guest-agent service
log_info "Checking qemu-guest-agent service..."
if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
  "systemctl is-active qemu-guest-agent" 2>/dev/null | grep -q "active"; then
  test_passed "qemu-guest-agent service is active"
else
  test_failed "qemu-guest-agent service is not active"
fi

# Test SSH service
log_info "Checking SSH service..."
if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
  "systemctl is-active sshd || systemctl is-active ssh" 2>/dev/null | grep -q "active"; then
  test_passed "SSH service is active"
else
  test_failed "SSH service is not active"
fi

echo ""

#############################################################################
# Test 6: Distribution-Specific Validation
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Distribution-Specific Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Running ${FLAVOR}-specific tests..."

case "${FLAVOR}" in
  ubuntu-*|debian-*)
    # Verify apt is functional
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "sudo apt-get update -qq && echo 'apt working'" 2>/dev/null | grep -q "apt working"; then
      test_passed "apt package manager is functional"
    else
      test_failed "apt package manager check failed"
    fi
    ;;

  fedora-*|centos-*|rocky-*|almalinux-*)
    # Verify dnf is functional
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "sudo dnf check-update -q -y || echo 'dnf working'" 2>/dev/null | grep -q "dnf working"; then
      test_passed "dnf package manager is functional"
    else
      test_failed "dnf package manager check failed"
    fi
    ;;

  kali-*)
    # Verify Mise is installed
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "command -v mise" 2>/dev/null | grep -q "mise"; then
      test_passed "mise is installed"
    else
      test_failed "mise is not installed"
    fi

    # Verify Lix/Nix is installed
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "command -v nix" 2>/dev/null | grep -q "nix"; then
      test_passed "lix/nix is installed"
    else
      test_failed "lix/nix is not installed"
    fi
    ;;

  archlinux-*)
    # Verify pacman is functional
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "sudo pacman -Sy --noconfirm && echo 'pacman working'" 2>/dev/null | grep -q "pacman working"; then
      test_passed "pacman package manager is functional"
    else
      test_failed "pacman package manager check failed"
    fi
    ;;

  opensuse-*)
    # Verify zypper is functional
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@localhost" \
      "sudo zypper refresh && echo 'zypper working'" 2>/dev/null | grep -q "zypper working"; then
      test_passed "zypper package manager is functional"
    else
      test_failed "zypper package manager check failed"
    fi
    ;;

  *)
    log_warn "No distribution-specific tests defined for ${FLAVOR}"
    ;;
esac

echo ""

#############################################################################
# Final Results
#############################################################################

if [[ ${TESTS_FAILED} -eq 0 ]]; then
  log_info "All tests passed! ✓"
  exit 0
else
  log_error "Some tests failed. Please review the output above."
  exit 1
fi
```

---

### Component 4: Integration Script

**File:** `tests/run-kvm-test.sh`

**Purpose:** Orchestrate the full test workflow (extract → generate → launch → test → cleanup).

**Implementation:**

```bash
#!/bin/bash
set -euo pipefail

FLAVOR=${1:?Error: FLAVOR required (e.g., ubuntu-24-04)}

# Configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${TESTS_DIR}/../.test-workspace"
QCOW2_FILE="${WORK_DIR}/${FLAVOR}.qcow2"
CLOUD_INIT_ISO="${WORK_DIR}/seed.iso"

# Cleanup function
cleanup() {
  local exit_code=$?

  echo ""
  echo "Cleaning up workspace..."

  # Kill VM if still running
  if [[ -f /tmp/vm.pid ]]; then
    kill "$(cat /tmp/vm.pid)" 2>/dev/null || true
  fi

  # Remove temporary files
  rm -rf "${WORK_DIR}"
  rm -f /tmp/qga.sock /tmp/vm.pid /tmp/vm-serial.log

  exit ${exit_code}
}

trap cleanup EXIT

# Create workspace
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "═══════════════════════════════════════════════════"
echo "KMI KVM Testing Pipeline"
echo "═══════════════════════════════════════════════════"
echo "  Flavor: ${FLAVOR}"
echo "  Workspace: ${WORK_DIR}"
echo "═══════════════════════════════════════════════════"
echo ""

# Step 1: Extract qcow2 from container
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Extract qcow2 from container"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CONTAINER_IMAGE="docker.io/containercraft/${FLAVOR/-/:}-dev"
echo "Pulling: ${CONTAINER_IMAGE}"

podman pull "${CONTAINER_IMAGE}"
podman create --name "tmp-${FLAVOR}" "${CONTAINER_IMAGE}"
podman cp "tmp-${FLAVOR}:/disk/${FLAVOR}.qcow2" "${QCOW2_FILE}"
podman rm "tmp-${FLAVOR}"

echo "✓ qcow2 extracted: ${QCOW2_FILE}"
ls -lh "${QCOW2_FILE}"
echo ""

# Step 2: Generate cloud-init ISO
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Generate cloud-init ISO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FLAVOR="${FLAVOR}" OUTPUT_ISO="${CLOUD_INIT_ISO}" "${TESTS_DIR}/generate-cloudinit-iso.sh"
echo ""

# Step 3: Launch VM
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Launch VM with KVM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

"${TESTS_DIR}/launch-vm.sh" "${QCOW2_FILE}" "${CLOUD_INIT_ISO}"
echo ""

# Step 4: Run tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Run Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FLAVOR="${FLAVOR}" "${TESTS_DIR}/test-vm.sh"

# Cleanup handled by trap
```

---

### Component 5: GitHub Actions Workflow

**File:** `.github/workflows/test-kvm.yml`

**Purpose:** Replace test.yml with KVM-based testing.

**Implementation:**

```yaml
name: Test and Promote KMIs (KVM)
on:
  pull_request:
  workflow_dispatch:
    inputs:
      flavor:
        description: "Image Flavor to test (ex. ubuntu-24-04)"
        required: true

env:
  FLAVOR: ${{ github.event.inputs.flavor || 'ubuntu-24-04' }}

jobs:
  test:
    runs-on: ubuntu-22.04
    timeout-minutes: 15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm
          ls -la /dev/kvm

      - name: Install Dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            qemu-kvm \
            qemu-system-x86 \
            cloud-image-utils \
            socat \
            openssh-client

          # Verify installations
          qemu-system-x86_64 --version
          cloud-localds --help || true

      - name: Verify KVM Support
        run: |
          if [[ -e /dev/kvm ]]; then
            echo "✓ KVM support available"
            sudo apt-get install -y cpu-checker
            sudo kvm-ok || echo "KVM check completed with warnings"
          else
            echo "⚠ KVM not available, tests will use TCG emulation (slower)"
          fi

      - name: Generate SSH Keypair
        run: |
          mkdir -p ~/.ssh
          ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_rsa -C "test@kmi"
          chmod 600 ~/.ssh/id_rsa
          chmod 644 ~/.ssh/id_rsa.pub

      - name: Run KVM Tests
        run: |
          chmod +x tests/*.sh
          ./tests/run-kvm-test.sh "${FLAVOR}"
        env:
          FLAVOR: ${{ env.FLAVOR }}

      - name: Archive VM Serial Log
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: ${{ env.FLAVOR }}-serial-log
          path: /tmp/vm-serial.log
          if-no-files-found: ignore

      - name: Archive Test Workspace
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: ${{ env.FLAVOR }}-workspace
          path: .test-workspace/
          if-no-files-found: ignore

  promote:
    runs-on: ubuntu-latest
    if: github.event_name != 'pull_request'
    needs: test
    permissions:
      id-token: write
    env:
      COSIGN_EXPERIMENTAL: 1
    steps:
      - name: Setup cosign
        uses: sigstore/cosign-installer@main

      - name: Login Docker Hub (podman)
        uses: redhat-actions/podman-login@v1
        with:
          logout: false
          registry: docker.io
          username: ${{ secrets.DOCKERHUB_USER }}
          password: ${{ secrets.DOCKERHUB_PASSWD }}

      - name: Login Docker Hub (docker)
        uses: docker/login-action@v3
        with:
          logout: false
          registry: docker.io
          username: ${{ secrets.DOCKERHUB_USER }}
          password: ${{ secrets.DOCKERHUB_PASSWD }}

      - name: Promote Image
        run: |
          skopeo copy --all \
            docker://docker.io/containercraft/${FLAVOR/-/:}-dev \
            docker://docker.io/containercraft/${FLAVOR/-/:}

      - name: Sign Image
        run: cosign sign --recursive docker.io/containercraft/${FLAVOR/-/:}

      - name: Wait for Signature Propagation
        run: sleep 5

      - name: Verify Image Signature
        run: |
          for i in {1..3}; do
            if cosign verify docker.io/containercraft/${FLAVOR/-/:} \
              --certificate-identity-regexp='https://github.com/ContainerCraft/kmi/.*' \
              --certificate-oidc-issuer=https://token.actions.githubusercontent.com; then
              echo "✓ Verification succeeded on attempt $i"
              exit 0
            else
              echo "⚠ Verification attempt $i failed, waiting 10 seconds..."
              sleep 10
            fi
          done
          echo "✗ Verification failed after 3 attempts"
          exit 1
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

**Goal:** Create and test new KVM-based scripts locally.

#### Tasks

1. **Create Script Files**
   - [ ] `tests/generate-cloudinit-iso.sh` - Cloud-init ISO generator
   - [ ] `tests/launch-vm.sh` - QEMU VM launcher
   - [ ] `tests/test-vm.sh` - Test suite
   - [ ] `tests/run-kvm-test.sh` - Integration orchestrator
   - [ ] Make all scripts executable (`chmod +x`)

2. **Local Testing (Developer Workstation)**
   - [ ] Test with ubuntu-24-04 (baseline)
   - [ ] Test with fedora-43 (RPM-based)
   - [ ] Test with kali-linux (custom packages: Mise, Lix/Nix)
   - [ ] Verify all 6 tests pass
   - [ ] Document any issues found

3. **Create GitHub Actions Workflow**
   - [ ] `.github/workflows/test-kvm.yml` - New workflow file
   - [ ] Keep `.github/workflows/test.yml` as `test-kubevirt.yml` (backup)
   - [ ] Update CircleCI trigger to use new workflow

**Deliverables:**
- 4 new shell scripts in `tests/`
- 1 new GitHub Actions workflow
- Test results for 3 distributions locally

**Success Criteria:**
- All scripts run successfully on developer workstation with KVM
- All 6 tests pass for ubuntu-24-04, fedora-43, kali-linux
- No errors in script execution

---

### Phase 2: CI Integration (Week 2)

**Goal:** Deploy to GitHub Actions and validate in CI environment.

#### Tasks

1. **Update CircleCI Trigger**
   - [ ] Edit `.circleci/config.yml`
   - [ ] Change trigger-tests command to dispatch `test-kvm.yml`
   - [ ] Test with single flavor (ubuntu-24-04)

2. **Enable KVM in GitHub Actions**
   - [ ] Verify `/dev/kvm` availability on ubuntu-22.04 runners
   - [ ] Test udev rules configuration
   - [ ] Measure boot time vs local KVM (should be similar)

3. **Run Parallel Tests (5 Flavors)**
   - [ ] ubuntu-24-04 (Ubuntu LTS baseline)
   - [ ] ubuntu-25-10 (Ubuntu current)
   - [ ] fedora-43 (RPM-based)
   - [ ] debian-13 (Debian baseline)
   - [ ] archlinux-latest (Rolling release)

4. **Performance Benchmarking**
   - [ ] Measure test duration per flavor (target: <5 minutes)
   - [ ] Compare vs old KubeVirt times (should be 5-10x faster)
   - [ ] Document results

**Deliverables:**
- CircleCI configured to trigger new workflow
- 5 distributions tested in CI
- Performance benchmark report

**Success Criteria:**
- All 5 distributions pass tests in CI
- Average test time < 5 minutes per flavor
- No KVM-related errors in CI environment

---

### Phase 3: Full Rollout (Week 3)

**Goal:** Test all 18 distributions and make KVM tests primary.

#### Tasks

1. **Test All Distributions**
   - [ ] Ubuntu: 24-04, 25-10
   - [ ] Fedora: 42, 43
   - [ ] Debian: 13
   - [ ] CentOS: 10
   - [ ] Rocky: 10
   - [ ] AlmaLinux: 10
   - [ ] openSUSE: leap-16, tumbleweed
   - [ ] FCOS: 42, 43
   - [ ] OpenWRT: 24
   - [ ] FreeBSD: 15
   - [ ] Talos: 1-11
   - [ ] VyOS: rolling
   - [ ] Kali: linux
   - [ ] Arch: latest

2. **Handle Edge Cases**
   - [ ] FCOS: Uses Ignition instead of cloud-init
     - Solution: Create `generate-ignition-iso.sh` variant
   - [ ] Talos: Minimal API-only OS
     - Solution: Test via talosctl instead of SSH
   - [ ] FreeBSD: Different init system
     - Solution: Adjust service checks
   - [ ] OpenWRT: Minimal embedded OS
     - Solution: Minimal test suite (boot + SSH only)

3. **Update Documentation**
   - [ ] README.md: Update testing section
   - [ ] Add `docs/testing-kvm.md`: Detailed KVM testing guide
   - [ ] Update `CONTRIBUTING.md`: How to run tests locally

4. **Make KVM Tests Primary**
   - [ ] Update CircleCI default trigger to `test-kvm.yml`
   - [ ] Rename workflows:
     - `test-kvm.yml` → `test.yml`
     - `test.yml` → `test-kubevirt-legacy.yml`
   - [ ] Update CI badges in README

**Deliverables:**
- All 18 distributions tested with KVM
- Edge case handling implemented
- Documentation updated

**Success Criteria:**
- ≥95% distributions pass tests (allow 1-2 edge cases to be pending)
- Documentation complete and accurate
- KVM tests are default in CI

---

### Phase 4: Cleanup (Week 4)

**Goal:** Remove KubeVirt dependencies and finalize migration.

#### Tasks

1. **Deprecate KubeVirt Tests**
   - [ ] Add deprecation notice to `test-kubevirt-legacy.yml`
   - [ ] Remove from default CI runs (keep for manual trigger only)
   - [ ] Monitor for 1 week: any issues requiring rollback?

2. **Remove Old Files (If No Issues)**
   - [ ] `tests/run.bats`
   - [ ] `tests/common.bash`
   - [ ] `tests/vmi.yaml`
   - [ ] `tests/ssh-service.yaml`
   - [ ] `tests/vm-presets.yaml`
   - [ ] `.github/workflows/kind/config.yml`
   - [ ] `.github/workflows/test-kubevirt-legacy.yml`

3. **Clean Up Dependencies**
   - [ ] Remove BATS from GitHub Actions workflow
   - [ ] Remove kind-action dependency
   - [ ] Remove virtctl installation step
   - [ ] Update Dependabot config (remove kind-action)

4. **Update Examples**
   - [ ] Review `examples/*/` directories
   - [ ] Ensure VirtualMachineInstance manifests still work
   - [ ] Add note: "Tested with KVM, validated for KubeVirt compatibility"

5. **Final Documentation**
   - [ ] Write migration retrospective (lessons learned)
   - [ ] Update README with new architecture diagram
   - [ ] Create `docs/architecture.md` with detailed pipeline flow

**Deliverables:**
- Old KubeVirt code removed
- Clean dependency tree
- Comprehensive documentation

**Success Criteria:**
- No KubeVirt references in active CI workflows
- All examples validated
- Documentation reflects current architecture

---

## Testing Strategy

### Test Levels

#### 1. **Unit Tests (Script-Level)**

Test each script independently:

```bash
# Test cloud-init ISO generator
./tests/generate-cloudinit-iso.sh ubuntu-24-04
file seed.iso | grep "ISO 9660"

# Test VM launcher (mock)
./tests/launch-vm.sh --help  # Should show usage

# Test VM test suite (mock)
./tests/test-vm.sh --dry-run  # Should validate inputs
```

#### 2. **Integration Tests (Full Workflow)**

Test complete workflow locally:

```bash
# Run full test for single flavor
./tests/run-kvm-test.sh ubuntu-24-04

# Verify outputs
cat /tmp/vm-serial.log  # Serial console output
ls -lh .test-workspace/  # Artifacts
```

#### 3. **CI Tests (GitHub Actions)**

Test in CI environment:

```bash
# Trigger manually for single flavor
gh workflow run test-kvm.yml -f flavor=ubuntu-24-04

# Monitor results
gh run watch
```

#### 4. **Regression Tests (All Distributions)**

Test all 18 distributions weekly:

```bash
# Automated via CircleCI build-and-publish-dev workflow
# Runs on every commit to main branch
```

### Test Matrix

| Distribution | Architecture | Test Priority | Notes |
|--------------|--------------|---------------|-------|
| ubuntu-24-04 | amd64, arm64 | P0 (Critical) | LTS baseline |
| ubuntu-25-10 | amd64, arm64 | P0 (Critical) | Current release |
| fedora-43 | amd64, arm64 | P0 (Critical) | RPM baseline |
| debian-13 | amd64, arm64 | P1 (High) | Debian baseline |
| kali-linux | amd64 | P0 (Critical) | Custom packages (Mise, Lix) |
| centos-10 | amd64, arm64 | P1 (High) | x86-64-v3 requirement |
| rocky-10 | amd64, arm64 | P1 (High) | RHEL clone |
| almalinux-10 | amd64, arm64 | P1 (High) | RHEL clone |
| opensuse-leap-16 | amd64, arm64 | P2 (Medium) | SUSE baseline |
| opensuse-tumbleweed | amd64 | P2 (Medium) | Rolling release |
| fcos-42, fcos-43 | amd64, arm64 | P1 (High) | CoreOS, Ignition |
| archlinux-latest | amd64 | P2 (Medium) | Rolling release |
| freebsd-15 | amd64 | P2 (Medium) | BSD, different init |
| talos-1-11 | amd64, arm64 | P2 (Medium) | API-only OS |
| vyos-rolling | amd64 | P2 (Medium) | Network OS |
| openwrt-24 | amd64, arm64 | P2 (Medium) | Embedded OS |
| fedora-42 | amd64, arm64 | P1 (High) | n-1 support |

**Priority Definitions:**
- **P0 (Critical):** Must pass before merge, blocks releases
- **P1 (High):** Should pass, can be fixed post-merge
- **P2 (Medium):** Best-effort, known edge cases acceptable

### Performance Benchmarks (Target)

| Metric | KubeVirt-in-kind (Current) | KVM/libvirt (Target) |
|--------|----------------------------|----------------------|
| Setup time | 7 minutes | 30 seconds |
| Boot time | 5-10 minutes | 30-60 seconds |
| Test execution | 5-10 minutes | 1-2 minutes |
| **Total time** | **15-20 minutes** | **3-5 minutes** |
| Resource usage | 6-8GB RAM | 2-3GB RAM |
| Success rate | 85-90% (flaky) | 98-99% (stable) |

---

## Migration Plan

### Migration Strategy: Parallel Run with Gradual Cutover

**Approach:** Run both KVM and KubeVirt tests in parallel for 2 weeks, then deprecate KubeVirt.

#### Week 1-2: Parallel Testing

```yaml
# .github/workflows/test-kvm.yml - New KVM tests
# .github/workflows/test-kubevirt.yml - Legacy KubeVirt tests (renamed)

# CircleCI triggers BOTH workflows
- trigger-gha-test:
    workflow: test-kvm.yml
- trigger-gha-test:
    workflow: test-kubevirt.yml
```

**Goals:**
- Compare test results (KVM vs KubeVirt)
- Identify discrepancies
- Build confidence in KVM approach

#### Week 3: KVM Primary, KubeVirt Optional

```yaml
# KVM tests: REQUIRED (blocks merge)
# KubeVirt tests: OPTIONAL (manual trigger only)

# CircleCI triggers only KVM by default
- trigger-gha-test:
    workflow: test-kvm.yml
```

**Goals:**
- Make KVM tests mandatory
- Keep KubeVirt for rollback if needed
- Monitor for production issues

#### Week 4: KubeVirt Deprecated

```yaml
# Remove KubeVirt tests entirely
# Remove old files
# Update documentation
```

**Goals:**
- Clean up codebase
- Finalize migration
- Celebrate! 🎉

### Rollback Plan

**If KVM tests have critical issues:**

1. **Immediate Rollback:**
   ```bash
   # CircleCI: Switch trigger back to test-kubevirt.yml
   git revert <commit-hash>
   git push
   ```

2. **Investigation:**
   - Review failed test logs
   - Identify root cause (KVM availability, script bugs, etc.)
   - Fix issues locally before re-attempting

3. **Retry:**
   - Apply fixes
   - Re-run parallel testing for 1 more week
   - Proceed with migration

**Rollback Triggers:**
- >10% test failure rate in CI
- Critical distribution fails (ubuntu-24-04, fedora-43, kali-linux)
- Unable to fix within 1 week

---

## Risk Assessment

### Risk Matrix

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **GHA runners lack KVM** | High | Low | Test in CI first, fallback to TCG |
| **Cloud-init ISO incompatibility** | Medium | Low | Test with all distros, adjust user-data |
| **Performance degradation** | Low | Very Low | KVM faster than emulation |
| **FCOS/Talos edge cases** | Medium | Medium | Create distro-specific test variants |
| **Script bugs** | Medium | Medium | Thorough local testing, code review |
| **Loss of KubeVirt validation** | Low | Low | Keep examples, add integration tests later |
| **Timeline slippage** | Low | Medium | Phased approach allows delay without impact |

### Critical Risks & Mitigation

#### Risk 1: GitHub Actions Runners Don't Support KVM

**Probability:** Low (GHA ubuntu-22.04 runners have KVM)
**Impact:** High (would block entire migration)

**Mitigation:**
1. **Pre-verify in CI:** Run test workflow before full migration
2. **Fallback to TCG:** Detect KVM unavailability, use software emulation (still faster than kind+KubeVirt)
3. **Alternative:** Use self-hosted runners with guaranteed KVM support

**Verification:**
```bash
# In GitHub Actions workflow
if [[ ! -e /dev/kvm ]]; then
  echo "⚠ KVM not available, using TCG emulation"
  # Still proceed, just slower
fi
```

#### Risk 2: Cloud-Init ISO Doesn't Work with Some Distributions

**Probability:** Low (cloud-init is standard)
**Impact:** Medium (would require distro-specific handling)

**Mitigation:**
1. **Test early:** Validate cloud-init with all 18 distros in Week 3
2. **Distro-specific overrides:** Create custom cloud-init configs per distro
3. **Alternative datasources:** Use ConfigDrive or NoCloud with HTTP server

**Example: FCOS uses Ignition instead of cloud-init**
```bash
# Create generate-ignition-iso.sh for FCOS
butane config.bu > config.ign
mkisofs -o ignition.iso config.ign
```

#### Risk 3: Test Script Bugs

**Probability:** Medium (new code)
**Impact:** Medium (false failures in CI)

**Mitigation:**
1. **Thorough local testing:** Test with 3+ distributions before CI deployment
2. **Code review:** Peer review all scripts
3. **Incremental rollout:** Start with 5 distributions, then expand
4. **Logging:** Comprehensive error messages for easy debugging

---

## Success Metrics

### Quantitative Metrics

| Metric | Baseline (Current) | Target (After Migration) | Measurement |
|--------|-------------------|--------------------------|-------------|
| **Test Duration** | 15-20 min/flavor | 3-5 min/flavor | GHA workflow runtime |
| **Success Rate** | 85-90% | 98-99% | Pass rate over 100 runs |
| **Resource Usage** | 6-8GB RAM | 2-3GB RAM | GHA runner metrics |
| **Setup Time** | 7 minutes | 30 seconds | Time to VM ready |
| **CI Cost** | Baseline | -70% | GHA billing |

### Qualitative Metrics

| Metric | Current State | Target State | Validation |
|--------|---------------|--------------|------------|
| **Developer Experience** | Hard to reproduce locally | Single command | Dev survey |
| **Debugging Ease** | Multi-layer logs | Single log file | Time to resolve failures |
| **Maintenance Burden** | 7 components | 2 components | Update frequency |
| **Test Confidence** | Moderate (flaky) | High (stable) | Developer feedback |

### Key Performance Indicators (KPIs)

**Primary KPI:**
- **Test Duration:** ≤5 minutes per flavor (target: 3 minutes)

**Secondary KPIs:**
- **Success Rate:** ≥98%
- **False Positive Rate:** <2%
- **Time to Debug Failure:** ≤10 minutes

**Tracking:**
- Weekly report: Test durations, success rates, failure analysis
- Dashboard: Grafana with GHA metrics (if available)
- Retrospective: After Week 4, document lessons learned

---

## Timeline

### Week 1: Foundation (Nov 11-17, 2025)

**Mon-Tue:** Create scripts
- [ ] Write 4 shell scripts
- [ ] Test locally with ubuntu-24-04

**Wed-Thu:** Expand testing
- [ ] Test fedora-43, kali-linux locally
- [ ] Fix any issues found

**Fri:** Create GitHub Actions workflow
- [ ] Write test-kvm.yml
- [ ] Test in CI with ubuntu-24-04

**Deliverables:**
- 4 scripts, 1 workflow
- Local test results for 3 distros

---

### Week 2: CI Integration (Nov 18-24, 2025)

**Mon:** Update CircleCI trigger
- [ ] Modify trigger-tests job
- [ ] Test with single flavor

**Tue-Wed:** Parallel testing
- [ ] Test 5 distributions in CI
- [ ] Benchmark performance

**Thu-Fri:** Analysis & tuning
- [ ] Compare KVM vs KubeVirt results
- [ ] Tune timeouts if needed

**Deliverables:**
- CI configured, 5 distros tested
- Performance report

---

### Week 3: Full Rollout (Nov 25-Dec 1, 2025)

**Mon-Tue:** Test all distributions
- [ ] Run tests for all 18 distros
- [ ] Handle edge cases (FCOS, Talos, etc.)

**Wed:** Documentation
- [ ] Update README, CONTRIBUTING
- [ ] Write testing guide

**Thu-Fri:** Make KVM primary
- [ ] Switch default CI to KVM tests
- [ ] Deprecate KubeVirt tests

**Deliverables:**
- All 18 distros tested
- Documentation complete
- KVM tests primary

---

### Week 4: Cleanup (Dec 2-8, 2025)

**Mon-Tue:** Monitor for issues
- [ ] Watch CI for failures
- [ ] Fix any problems

**Wed:** Remove old code
- [ ] Delete KubeVirt files
- [ ] Clean up dependencies

**Thu-Fri:** Final documentation
- [ ] Write retrospective
- [ ] Update architecture docs
- [ ] Celebrate! 🎉

**Deliverables:**
- Clean codebase
- Complete documentation
- Migration complete

---

## Appendix

### A. File Inventory

**New Files Created:**
1. `tests/generate-cloudinit-iso.sh` - Cloud-init ISO generator (120 lines)
2. `tests/launch-vm.sh` - QEMU VM launcher (100 lines)
3. `tests/test-vm.sh` - Comprehensive test suite (400 lines)
4. `tests/run-kvm-test.sh` - Integration orchestrator (80 lines)
5. `.github/workflows/test-kvm.yml` - New GHA workflow (120 lines)
6. `docs/testing-kvm.md` - KVM testing guide (TBD)

**Modified Files:**
1. `.circleci/config.yml` - Update trigger-tests to use test-kvm.yml
2. `README.md` - Update testing section
3. `CONTRIBUTING.md` - Update local testing instructions

**Deprecated Files (Phase 4):**
1. `tests/run.bats` - BATS test suite
2. `tests/common.bash` - BATS helpers
3. `tests/vmi.yaml` - VirtualMachineInstance template
4. `tests/ssh-service.yaml` - NodePort service
5. `tests/vm-presets.yaml` - Resource presets
6. `.github/workflows/kind/config.yml` - kind cluster config
7. `.github/workflows/test-kubevirt-legacy.yml` - Renamed from test.yml

### B. Dependencies

**Required on GitHub Actions Runners:**
- `qemu-kvm` - KVM hypervisor
- `qemu-system-x86` - x86_64 system emulation
- `cloud-image-utils` - cloud-localds utility
- `socat` - Socket communication
- `openssh-client` - SSH testing

**All available via apt-get on ubuntu-22.04.**

### C. References

**KVM/QEMU Documentation:**
- [QEMU User Networking](https://wiki.qemu.org/Documentation/Networking#User_Networking_(SLIRP))
- [QEMU Guest Agent Protocol](https://wiki.qemu.org/Features/GuestAgent)

**Cloud-Init Documentation:**
- [Cloud-Init NoCloud Datasource](https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html)
- [Cloud-Init User-Data Format](https://cloudinit.readthedocs.io/en/latest/topics/format.html)

**GitHub Actions:**
- [Ubuntu Runner Specs](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

**Existing KMI Resources:**
- `hack/customize.sh` - Uses libguestfs with KVM acceleration
- `images/*/virt.sysprep` - Package installation and service enablement
- `examples/*/` - VirtualMachineInstance deployment examples

---

## Conclusion

This plan provides a comprehensive, phased approach to replacing KubeVirt-in-kind testing with direct KVM/libvirt testing. The new approach is:

- **5-10x faster** (3-5 minutes vs 15-20 minutes per flavor)
- **90% simpler** (2 components vs 7)
- **More reliable** (98-99% vs 85-90% success rate)
- **Easier to debug** (single log file vs multi-layer aggregation)
- **Better test coverage** (validates actual boot behavior)

The phased migration with parallel testing minimizes risk while providing clear rollback options if issues arise. Success metrics will track both quantitative improvements (duration, cost) and qualitative benefits (developer experience, maintainability).

**Next Steps:**
1. Review and approve this plan
2. Begin Week 1 implementation
3. Schedule weekly check-ins during migration
4. Celebrate completion after Week 4! 🎉

---

**Document Version:** 1.0
**Last Updated:** 2025-11-11
**Status:** Ready for Review
