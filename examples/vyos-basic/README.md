# VyOS Basic Router Example

A simple, ephemeral VyOS router VM for KubeVirt using the `containercraft/vyos:rolling` image.

## Overview

This example deploys a basic VyOS router with:
- **eth0**: WAN interface (connected to Multus br1 network - upstream)
- **eth1**: LAN interface (connected to Multus br0 network - downstream)
- NAT from LAN to WAN
- DHCP server for LAN (192.168.1.0/24)
- DNS forwarding
- Basic firewall rules
- SSH access on port 2222

## Architecture

```
┌─────────────────────────────────────┐
│         Kubernetes Cluster          │
│                                     │
│  ┌───────────────────────────────┐  │
│  │     VyOS Router VM            │  │
│  │                               │  │
│  │  ┌─────────┐    ┌─────────┐  │  │
│  │  │  eth0   │    │  eth1   │  │  │
│  │  │  (WAN)  │    │  (LAN)  │  │  │
│  │  │  DHCP   │    │192.168  │  │  │
│  │  │         │    │  .1.1   │  │  │
│  │  └────┬────┘    └────┬────┘  │  │
│  │       │              │        │  │
│  └───────┼──────────────┼────────┘  │
│          │              │           │
│    ┌─────▼───┐    ┌────▼─────┐     │
│    │ Multus  │    │  Multus  │     │
│    │   br1   │    │   br0    │     │
│    └─────────┘    └──────────┘     │
│    (WAN/          (LAN/            │
│     Upstream)      Downstream)     │
└─────────────────────────────────────┘
```

## Prerequisites

1. **KubeVirt** installed on your Kubernetes cluster
2. **Multus CNI** installed and configured
3. **Linux bridge** interfaces on your nodes:
   - `br1` - WAN/upstream bridge (must exist on nodes)
   - `br0` - LAN/downstream bridge (must exist on nodes)
4. **kubectl** with access to the cluster
5. **virtctl** for console access (optional)

**Note**: The `deploy.sh` script will automatically create the required NetworkAttachmentDefinitions (`wan-br1` and `lan-br0`) that reference the node bridges `br1` and `br0`.

## Configuration

### Network Configuration

- **WAN (eth0)**:
  - Connected to Multus br1 network
  - DHCP client (gets IP from upstream network)
  - Firewall: Drop all incoming, allow established/related
  - SSH rate limiting enabled

- **LAN (eth1)**:
  - Static IP: `192.168.1.1/24`
  - DHCP range: `192.168.1.100` - `192.168.1.200`
  - DNS forwarding to 1.1.1.1 and 8.8.8.8
  - Domain: `home.arpa`

- **NAT**: Masquerade LAN traffic to WAN

### SSH Access

- Port: `2222`
- Authentication: SSH key only (password auth disabled)
- Public key is configured in `cloud-config.userdata`

## Deployment

### Quick Start

```bash
cd examples/vyos-basic
./deploy.sh
```

### Manual Deployment

```bash
# Create NetworkAttachmentDefinitions
kubectl apply -f net-attach-def-wan-br1.yaml
kubectl apply -f net-attach-def-lan-br0.yaml

# Create the cloud-init secret
kubectl create secret generic vyos-basic-config \
  --from-file=userdata=cloud-config.userdata

# Deploy the VM
kubectl apply -f vyos-vm.yaml

# Wait for the VM to be ready
kubectl wait --for=condition=Ready vm/vyos-basic --timeout=300s

# Check status
kubectl get vm,vmi vyos-basic
kubectl get net-attach-def
```

## Accessing the Router

### Console Access

```bash
# Using virtctl
virtctl console vyos-basic

# Using kubectl
kubectl virt console vyos-basic
```

### SSH Access

Once the VM is running and has an IP address:

```bash
# Get the VM's IP address
kubectl get vmi vyos-basic -o jsonpath='{.status.interfaces[0].ipAddress}'

# Connect via SSH
ssh -p 2222 vyos@<vm-ip>
```

## Customization

### Modify Network Configuration

Edit `cloud-config.userdata` to change:
- LAN subnet and DHCP range
- DNS servers
- Firewall rules
- Additional VLANs or interfaces

### Change Multus Networks

Edit `vyos-vm.yaml` and update the network references:

```yaml
# WAN network (eth0)
- name: eth0
  multus:
    networkName: br1  # Change this

# LAN network (eth1)
- name: eth1
  multus:
    networkName: br0  # Change this
```

### Update VyOS Image

The VM uses `docker.io/containercraft/vyos:rolling` by default. To use a different version:

```yaml
- name: containerdisk
  containerDisk:
    image: docker.io/containercraft/vyos:your-tag
```

## Verification

### Check Interfaces

```bash
# In VyOS console
show interfaces
show ip address
```

### Check DHCP

```bash
show dhcp server leases
show dhcp server statistics
```

### Check NAT

```bash
show nat source rules
show nat source statistics
```

### Check Firewall

```bash
show firewall
show firewall statistics
```

## Troubleshooting

### VM Won't Start

```bash
# Check VM events
kubectl describe vm vyos-basic

# Check VMI (VirtualMachineInstance)
kubectl describe vmi vyos-basic

# Check pod logs
kubectl logs virt-launcher-vyos-basic-xxxxx
```

### Network Issues

```bash
# In VyOS console
show log tail
show configuration commands | grep interface
ping 1.1.1.1
```

### Cloud-init Not Applied

```bash
# Check cloud-init status in VyOS
show log cloud-init

# Verify secret exists
kubectl get secret vyos-basic-config -o yaml
```

## Cleanup

```bash
# Delete the VM
kubectl delete vm vyos-basic

# Delete the secret
kubectl delete secret vyos-basic-config

# Delete NetworkAttachmentDefinitions
kubectl delete -f net-attach-def-wan-br1.yaml
kubectl delete -f net-attach-def-lan-br0.yaml
```

## Notes

- This is an **ephemeral** deployment using containerDisk
- Configuration is applied via cloud-init on every boot
- No persistent storage is used
- Perfect for testing and development
- For production use, consider persistent storage for configuration

## Next Steps

- Add more interfaces for DMZ, IoT, etc.
- Configure VLANs on eth1
- Set up VPN (WireGuard, IPsec)
- Enable monitoring and logging
- Add static DHCP leases
- Configure port forwarding rules

## Related Documentation

- [VyOS Documentation](https://docs.vyos.io/)
- [KubeVirt Documentation](https://kubevirt.io/user-guide/)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)