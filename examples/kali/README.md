# Kali Linux 2025.3 Pentest Workstation Example

Deploy a fully-featured Kali Linux penetration testing workstation on KubeVirt with XRDP remote desktop access.

## Features

- **Kali Linux 2025.3** with all pentesting tools pre-installed
- **XRDP** remote desktop server for GUI access
- **Desktop Environment** (XFCE/GNOME/KDE - depending on Kali configuration)
- **Docker** for container-based testing
- **Wireshark** configured for non-root packet capture
- **SSH** access with key-based authentication
- **Bridge networking** via Multus for direct network access
- **Persistent storage** (128GB default, expandable)
- **Cloud-init** automated provisioning

## Quick Start

### Prerequisites

1. **KubeVirt cluster** with:
   - KubeVirt installed and configured
   - Multus CNI with `br0-network-attachment` NetworkAttachmentDefinition
   - Storage provisioner (e.g., `hostpath-provisioner`)

2. **Local tools**:
   - `kubectl` configured for your cluster
   - `virtctl` for VM management
   - SSH key pair (default: `~/.ssh/id_ed25519.pub`)

3. **Network configuration**:
   - Bridge interface `br0` configured on nodes
   - DHCP available on bridge network (or configure static IP)

### One-Command Deployment

```bash
./deploy.sh --monitor
```

This will:
1. Create SSH key secret from `~/.ssh/id_ed25519.pub`
2. Create cloud-init userdata secret
3. Deploy the VirtualMachine
4. Monitor startup and display connection information

### Custom Deployment

```bash
# Deploy with custom SSH key
./deploy.sh --ssh-key ~/.ssh/my_pentest_key.pub --monitor

# Deploy with custom userdata
./deploy.sh --userdata ./my-kali-userdata.yaml --monitor

# Deploy to specific namespace
./deploy.sh --namespace pentest-lab --monitor
```

## Manual Deployment

If you prefer manual steps:

### 1. Create Secrets

```bash
# SSH key secret
kubectl create secret generic kargo-sshpubkey-kali \
  --from-file=key1=$HOME/.ssh/id_ed25519.pub \
  --namespace=default

# Cloud-init userdata secret
kubectl create secret generic kali-linux-userdata \
  --from-file=userdata=kali-linux-userdata.yaml \
  --namespace=default
```

### 2. Verify Network Configuration

```bash
kubectl get net-attach-def br0-network-attachment
```

### 3. Deploy VirtualMachine

```bash
kubectl apply -f kali-linux-vdi-xrdp-gnome-br0-containerdisk.yaml
```

### 4. Monitor Deployment

```bash
# Watch VM resources
kubectl get vm,vmi,dv,pvc -w

# Get VM IP address
kubectl get vmi kali-linux-xrdp -o jsonpath='{.status.interfaces[0].ipAddress}'

# Access console
virtctl console kali-linux-xrdp
```

## Connecting to the VM

### SSH Access

```bash
# Get VM IP
VM_IP=$(kubectl get vmi kali-linux-xrdp -o jsonpath='{.status.interfaces[0].ipAddress}')

# Connect via SSH
ssh kali@$VM_IP
```

**Default credentials:**
- Username: `kali`
- Password: `kali`

### RDP Access

```bash
# Using xfreerdp
xfreerdp /v:$VM_IP:3389 /u:kali /p:kali /cert:ignore /size:1920x1080

# Using rdesktop
rdesktop -u kali -p kali $VM_IP:3389

# Using Microsoft Remote Desktop (macOS/Windows)
# Server: $VM_IP:3389
# Username: kali
# Password: kali
```

### Console Access

```bash
# Virtctl console (serial)
virtctl console kali-linux-xrdp

# Exit console: Ctrl+] or Ctrl+5
```

## Customization

### Resource Allocation

Edit the VM manifest to adjust resources:

```yaml
resources:
  requests:
    memory: 16Gi  # Adjust memory (8Gi, 16Gi, 32Gi)
  limits:
    memory: 16Gi

cpu:
  cores: 4        # Adjust CPU cores (2, 4, 8, etc.)
```

### Storage Size

Change storage allocation in DataVolumeTemplate:

```yaml
resources:
  requests:
    storage: 128Gi  # Adjust storage (128Gi, 256Gi, etc.)
```

### User Configuration

Edit `kali-linux-userdata.yaml` to customize:

- **Users and passwords**: Modify `chpasswd` section
- **SSH keys**: Update `ssh_import_id` with your GitHub username
- **Additional packages**: Add to `packages` list
- **Custom scripts**: Add to `runcmd` section
- **Network settings**: Modify bridge configuration

### Desktop Environment

Kali supports multiple desktop environments. The userdata automatically detects and configures:
- XFCE (Kali default)
- GNOME
- KDE Plasma

To change desktop, modify the Kali image or install via cloud-init:

```yaml
packages:
  - kali-desktop-gnome  # For GNOME
  # or
  - kali-desktop-kde    # For KDE
  # or
  - kali-desktop-xfce   # For XFCE (default)
```

## Pentesting Tools

Kali includes comprehensive penetration testing tools out of the box:

### Network Analysis
- Wireshark, tcpdump, nmap
- Netcat, socat, hping3
- Aircrack-ng suite

### Web Application Testing
- Burp Suite, ZAP
- Nikto, WPScan, SQLMap
- Dirb, Gobuster

### Exploitation
- Metasploit Framework
- ExploitDB, SearchSploit
- Social Engineering Toolkit

### Password Cracking
- John the Ripper, Hashcat
- Hydra, Medusa
- CrackMapExec

### Wireless Testing
- Aircrack-ng, Reaver, Wifite
- Kismet, Wifiphisher

### Forensics
- Autopsy, Volatility
- Binwalk, Foremost

For full tool list: https://www.kali.org/tools/

## Docker Support

Docker is pre-installed and configured:

```bash
# Run container-based tools
docker run -it kalilinux/kali-rolling

# Run specific tool containers
docker run -it remnux/remnux-distro
```

## Wireshark Configuration

Wireshark is configured for non-root packet capture:

```bash
# Capture on any interface as kali user
wireshark

# Or use tshark
tshark -i eth0
```

## Persistence

The VM uses a persistent 128GB disk for:
- User data (`/home/kali/`)
- Tool configurations
- Captured data and results
- Docker images and containers
- Custom scripts and exploits

Data persists across VM restarts.

## Security Considerations

### Production Use

For production penetration testing:

1. **Change default passwords** in userdata
2. **Use SSH key authentication only**: Disable password auth
3. **Network isolation**: Deploy in dedicated namespace/VLAN
4. **Enable firewall**: Configure iptables/ufw
5. **Audit logging**: Enable detailed logging
6. **Regular updates**: Keep tools and OS updated

### Network Segmentation

The VM uses bridge networking. Consider:

- Deploying in isolated network segments
- Using NetworkPolicies for pod-to-pod restrictions
- Implementing egress filtering
- Monitoring network traffic

## Troubleshooting

### VM Won't Start

```bash
# Check VM events
kubectl describe vm kali-linux-xrdp

# Check VMI status
kubectl get vmi kali-linux-xrdp -o yaml

# Check DataVolume
kubectl get dv,pvc
```

### No IP Address

```bash
# Check network attachment
kubectl get net-attach-def br0-network-attachment

# Verify bridge exists on node
ssh node-host ip link show br0

# Check DHCP logs in VM console
virtctl console kali-linux-xrdp
# Then: journalctl -u systemd-networkd
```

### RDP Connection Issues

```bash
# Check XRDP service in VM
virtctl console kali-linux-xrdp
# Then: systemctl status xrdp

# Verify port 3389 is reachable
nmap -p 3389 $VM_IP

# Check cloud-init logs
tail -f /var/log/cloud-init-output.log
```

### Cloud-init Failures

```bash
# Access VM console
virtctl console kali-linux-xrdp

# Check cloud-init status
cloud-init status --long

# View detailed logs
tail -f /var/log/cloud-init-output.log
cat /var/log/cloud-init.log
```

## Cleanup

### Remove VM and Resources

```bash
kubectl delete vm kali-linux-xrdp
kubectl delete pvc kali-linux-volume-vda-root
kubectl delete dv kali-linux-volume-vda-root
kubectl delete secret kali-linux-userdata
kubectl delete secret kargo-sshpubkey-kali
```

### Using the Deploy Script

```bash
# The deploy script doesn't include cleanup
# Use kubectl commands above or create a cleanup.sh script
```

## Advanced Usage

### Nested Virtualization

For running VMs inside the Kali VM:

1. Enable nested virtualization on KubeVirt nodes
2. Add `devices.kubevirt.io/kvm: "1"` to VM resources
3. Install KVM/QEMU in Kali

### Custom Kali Images

Build custom Kali images with additional tools:

```dockerfile
FROM docker.io/containercraft/kali:latest
RUN apt-get update && apt-get install -y \
    custom-tool-1 \
    custom-tool-2
```

Then update the VM manifest to use your custom image.

### Port Forwarding

Expose services via Kubernetes Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kali-rdp
spec:
  type: NodePort
  selector:
    app: kali-linux-xrdp
  ports:
    - name: rdp
      port: 3389
      targetPort: 3389
      nodePort: 30389
    - name: ssh
      port: 22
      targetPort: 22
      nodePort: 30022
```

## References

- [Kali Linux Documentation](https://www.kali.org/docs/)
- [Kali Linux Tools](https://www.kali.org/tools/)
- [KubeVirt Documentation](https://kubevirt.io/user-guide/)
- [XRDP Documentation](http://xrdp.org/)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)

## Support

For issues with:
- **Kali Linux tools**: Visit [Kali Forums](https://forums.kali.org/)
- **KMI images**: Open issue at [KMI GitHub](https://github.com/ContainerCraft/kmi/issues)
- **KubeVirt**: Check [KubeVirt Docs](https://kubevirt.io/)
