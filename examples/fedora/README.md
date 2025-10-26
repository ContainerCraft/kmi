# Fedora 42 Workstation VM Example

This example demonstrates deploying a fully-featured Fedora 42 Workstation VM with XRDP/GNOME desktop environment on KubeVirt.

## Features

- **Operating System**: Fedora 42 Workstation
- **Desktop Environment**: GNOME Desktop with XRDP remote access
- **Container Runtime**: Docker CE with docker-compose
- **Virtualization**: Full libvirt/KVM stack with virt-manager
- **Nested Virtualization**: Bridge networking (br0) for nested VMs with direct LAN access
- **Development Tools**: gcc, make, Python, Node.js, git, and more
- **System Resources**: 4 vCPUs, 16GB RAM, 64GB disk
- **Network**: enp1s0 bridged to br0 with DHCP (NetworkManager renderer)
- **Hardware**: Q35 machine type with comprehensive device support

## Quick Start

### Prerequisites

- KubeVirt installed and running
- `kubectl` configured with cluster access
- `virtctl` CLI tool (optional, for console access)
- Network Attachment Definition `br0-network-attachment` configured
- SSH public key at `~/.ssh/id_ed25519.pub` (or specify custom path)

### Deployment

#### Option 1: Automated Deployment (Recommended)

Use the deployment script for a fully automated setup:

```bash
./deploy.sh
```

With monitoring enabled:

```bash
./deploy.sh --monitor
```

With custom SSH key:

```bash
./deploy.sh --ssh-key ~/.ssh/my_custom_key.pub
```

#### Option 2: Manual Deployment

1. **Create SSH key secret:**
   ```bash
   kubectl create secret generic kargo-sshpubkey-kc2user \
     --from-file=key1=$HOME/.ssh/id_ed25519.pub \
     --namespace=default
   ```

2. **Create cloud-init userdata secret:**
   ```bash
   kubectl create secret generic fedora-42-userdata \
     --from-file=userdata=./fedora-42-userdata.yaml \
     --namespace=default
   ```

3. **Deploy the VM:**
   ```bash
   kubectl apply -f fedora-42-vdi-xrdp-gnome-br0-containerdisk.yaml
   ```

4. **Monitor deployment:**
   ```bash
   kubectl get vm,vmi,dv,pvc
   ```

5. **Get VM IP address:**
   ```bash
   kubectl get vmi fedora-42-xrdp-gnome -o jsonpath='{.status.interfaces[0].ipAddress}'
   ```

## Files

- **`fedora-42-vdi-xrdp-gnome-br0-containerdisk.yaml`** - Main VirtualMachine manifest
- **`fedora-42-userdata.yaml`** - Cloud-init configuration (used as secret)
- **`deploy.sh`** - Automated deployment script
- **`README.md`** - This file

## Accessing the VM

### SSH Access

```bash
ssh kc2user@<VM_IP>
```

**Credentials:**
- Username: `kc2user`
- Password: `kc2user`
- SSH keys from `~/.ssh/id_ed25519.pub` are automatically installed

### RDP Access (GNOME Desktop)

**Using xfreerdp:**
```bash
xfreerdp /v:<VM_IP>:3389 /u:kc2user /p:kc2user /cert:ignore
```

**Using rdesktop:**
```bash
rdesktop -u kc2user -p kc2user <VM_IP>:3389
```

**Using Remmina or Microsoft Remote Desktop:**
- Server: `<VM_IP>:3389`
- Username: `kc2user`
- Password: `kc2user`

### Console Access

```bash
virtctl console fedora-42-xrdp-gnome
```

## VM Configuration

### Hardware Specifications

| Component | Configuration |
|-----------|--------------|
| Machine Type | Q35 (modern chipset) |
| Firmware | BIOS |
| CPU | 4 cores (1 socket × 4 cores × 1 thread) |
| CPU Model | host-passthrough |
| Memory | 16GB |
| Storage | 64GB (hostpath-provisioner) |
| Network | 1× virtio bridge interface |
| Graphics | VGA with USB tablet |

### Device Features

- ACPI (Advanced Configuration and Power Interface)
- APIC (Advanced Programmable Interrupt Controller)
- SMM (System Management Mode)
- RNG (Random Number Generator)
- Serial Console
- Graphics Device
- Network Multiqueue

### Installed Software

**Base Utilities:**
- vim, git, tmux, htop, btop, ncdu, tree
- curl, wget, unzip, tar, rsync
- lnav, jq, socat
- net-tools, bind-utils, traceroute, telnet, nmap, tcpdump
- screen

**Desktop Environment:**
- GNOME Workstation (full installation)
- gnome-tweaks
- gnome-extensions-app
- gnome-shell-extension-appindicator
- gnome-shell-extension-dash-to-dock
- gnome-terminal
- gnome-terminal-nautilus

**Web Browser:**
- Microsoft Edge (stable)

**Remote Desktop:**
- xrdp
- xorgxrdp

**Virtualization:**
- Full virtualization group
- libvirt
- virt-manager
- virt-viewer
- QEMU guest agent

**Container Tools:**
- Docker CE
- docker-compose-plugin
- containerd.io

**Development Tools:**
- gcc, make
- Python 3 with pip
- Node.js with npm

## Cloud-init Configuration

The cloud-init userdata (`fedora-42-userdata.yaml`) configures:

1. **User Setup**: Creates `kc2user` with sudo access and Docker/libvirt groups
2. **SSH Keys**: Imports SSH keys from GitHub user `usrbinkat`
3. **Network**: DHCP on enp1s0 interface with NetworkManager renderer for native Fedora integration
4. **Packages**: Installs desktop environment, development tools, and container runtime
5. **Services**: Enables QEMU guest agent, Docker, libvirt, and XRDP
6. **Desktop**: Configures GNOME with XRDP for remote access
7. **Firewall**: Opens ports 22 (SSH), 80, 443, 3389 (RDP)

### Network Configuration

The VM uses cloud-init network config v2 with explicit NetworkManager renderer and a bridge configuration for nested virtualization:

```yaml
networkData: |
  version: 2
  renderer: NetworkManager
  ethernets:
    enp1s0:
      dhcp4: false
      dhcp6: false
  bridges:
    br0:
      interfaces: [enp1s0]
      dhcp4: true
      dhcp6: true
      dhcp-identifier: mac
```

**Why NetworkManager renderer?**
- Native integration with Fedora/RHEL systems
- Direct compatibility with GNOME network settings UI
- Generates configs in `/etc/NetworkManager/system-connections/` (standard for Fedora)
- While Fedora's cloud-init already prioritizes NetworkManager by default, explicitly setting it ensures consistent behavior

**Why bridge configuration?**
- Enables nested virtualization with direct LAN access
- VMs created in virt-manager can attach to `br0` bridge
- Nested VMs get IP addresses on the same LAN as the host VM
- The physical interface `enp1s0` is bridged, with `br0` handling DHCP
- This allows seamless network connectivity for multi-tier virtualization scenarios

### Customizing Cloud-init

To customize the VM configuration:

1. Edit `fedora-42-userdata.yaml`
2. Update the secret:
   ```bash
   kubectl delete secret fedora-42-userdata
   kubectl create secret generic fedora-42-userdata \
     --from-file=userdata=./fedora-42-userdata.yaml
   ```
3. Restart the VM:
   ```bash
   kubectl delete vmi fedora-42-xrdp-gnome
   ```

## Deployment Script Options

The `deploy.sh` script supports various options:

```bash
./deploy.sh [OPTIONS]

Options:
  --ssh-key PATH          Path to SSH public key (default: ~/.ssh/id_ed25519.pub)
  --userdata PATH         Path to cloud-init userdata file (default: ./fedora-42-userdata.yaml)
  --vm-manifest PATH      Path to VM manifest file (default: ./fedora-42-vdi-xrdp-gnome-br0-containerdisk.yaml)
  --namespace NAME        Kubernetes namespace (default: default)
  --skip-secrets         Skip secret creation (use existing secrets)
  --monitor              Monitor VM startup after deployment
  -h, --help             Show this help message
```

### Examples

**Deploy with custom userdata:**
```bash
./deploy.sh --userdata ./my-custom-userdata.yaml
```

**Deploy to different namespace:**
```bash
./deploy.sh --namespace my-namespace
```

**Deploy with existing secrets:**
```bash
./deploy.sh --skip-secrets
```

**Deploy and monitor startup:**
```bash
./deploy.sh --monitor
```

## Troubleshooting

### VM Not Starting

1. **Check VM status:**
   ```bash
   kubectl get vm,vmi -n default
   kubectl describe vmi fedora-42-xrdp-gnome
   ```

2. **Check DataVolume import:**
   ```bash
   kubectl get dv,pvc -n default
   kubectl describe dv fedora-42-volume-vda-root
   ```

3. **Check pod logs:**
   ```bash
   kubectl logs -l kubevirt.io/domain=fedora-42-xrdp-gnome --all-containers=true
   ```

### Network Issues

1. **Verify network attachment definition:**
   ```bash
   kubectl get net-attach-def br0-network-attachment
   ```

2. **Check VMI network status:**
   ```bash
   kubectl get vmi fedora-42-xrdp-gnome -o jsonpath='{.status.interfaces}'
   ```

### Cloud-init Issues

1. **Access console:**
   ```bash
   virtctl console fedora-42-xrdp-gnome
   ```

2. **Check cloud-init logs (from inside VM):**
   ```bash
   tail -f /var/log/cloud-init-output.log
   cloud-init status
   ```

3. **Verify secret exists:**
   ```bash
   kubectl get secret fedora-42-userdata -o yaml
   ```

### XRDP Connection Issues

1. **Verify XRDP is running (from inside VM):**
   ```bash
   systemctl status xrdp
   systemctl status xrdp-sesman
   ```

2. **Check firewall rules:**
   ```bash
   firewall-cmd --list-all
   ```

3. **Test from within cluster:**
   ```bash
   kubectl run -it --rm debug --image=alpine --restart=Never -- sh
   # Then try: telnet <VM_IP> 3389
   ```

## Cleanup

### Delete VM and Resources

```bash
kubectl delete vm fedora-42-xrdp-gnome
kubectl delete pvc fedora-42-volume-vda-root
kubectl delete dv fedora-42-volume-vda-root
```

### Delete Secrets

```bash
kubectl delete secret fedora-42-userdata
kubectl delete secret kargo-sshpubkey-kc2user
```

### Complete Cleanup (One Command)

```bash
kubectl delete vm fedora-42-xrdp-gnome && \
kubectl delete pvc fedora-42-volume-vda-root && \
kubectl delete dv fedora-42-volume-vda-root && \
kubectl delete secret fedora-42-userdata kargo-sshpubkey-kc2user
```

## Nested Virtualization

The VM is configured with a `br0` bridge on the physical `enp1s0` interface, enabling nested virtualization with direct LAN access.

### Creating Nested VMs in virt-manager

1. **Connect via RDP to access the graphical desktop**

2. **Open virt-manager:**
   ```bash
   virt-manager
   ```

3. **Create a new virtual machine:**
   - Click "Create a new virtual machine"
   - Choose your installation method (ISO, network, etc.)
   - Configure CPU, memory, and storage as needed

4. **Network Configuration:**
   - In the VM network settings, select "Bridge device"
   - Choose `br0` as the bridge interface
   - The nested VM will receive an IP address on the same LAN as the host VM

5. **Verify nested VM connectivity:**
   - The nested VM should get an IP on the same subnet as the Fedora host
   - Network traffic flows: Nested VM → br0 → enp1s0 → br0-network-attachment (Multus) → LAN

### Network Topology

```
LAN
 │
 └─ br0-network-attachment (Multus CNI)
     │
     └─ Fedora VM (enp1s0 → br0)
         │
         └─ Nested VMs (attached to br0)
```

All VMs (host and nested) share the same LAN, making it easy to:
- Access nested VMs from outside the KubeVirt cluster
- Run multi-tier application stacks
- Test complex networking scenarios
- Build development environments with multiple interconnected VMs

## Performance Tuning

### Increase Resources

Edit the VM manifest to adjust CPU/memory:

```yaml
cpu:
  cores: 8  # Increase from 4
resources:
  requests:
    memory: 32Gi  # Increase from 16Gi
```

### Dedicated CPU Placement

For better performance, enable dedicated CPU placement:

```yaml
cpu:
  dedicatedCpuPlacement: true
```

### Storage Performance

Use faster storage class for better I/O performance:

```yaml
storageClassName: fast-ssd-storage
```

## Security Considerations

1. **Change Default Passwords**: The default password `kc2user` should be changed in production
2. **SSH Keys**: Use SSH key authentication instead of passwords
3. **Firewall**: Restrict open ports to only what's needed
4. **Network Policy**: Implement Kubernetes NetworkPolicy for VM network isolation
5. **RBAC**: Use appropriate RBAC rules for VM management

## References

- [KubeVirt Documentation](https://kubevirt.io/user-guide/)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Fedora Documentation](https://docs.fedoraproject.org/)
- [XRDP Documentation](https://github.com/neutrinolabs/xrdp)

## License

This example configuration is provided as-is for reference and testing purposes.