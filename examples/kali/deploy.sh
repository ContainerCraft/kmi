#!/bin/bash
set -ex

#===============================================================================
# Kali Linux 2025.3 VM Deployment Script
#===============================================================================
# This script automates the deployment of Kali Linux VirtualMachine with:
# - SSH key secret creation
# - Cloud-init userdata secret creation
# - VirtualMachine resource deployment
# - Status monitoring
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --ssh-key PATH          Path to SSH public key (default: ~/.ssh/id_ed25519.pub)
#   --userdata PATH         Path to cloud-init userdata file (default: ./kali-linux-userdata.yaml)
#   --vm-manifest PATH      Path to VM manifest file (default: ./kali-linux-vdi-xrdp-gnome-br0-containerdisk.yaml)
#   --namespace NAME        Kubernetes namespace (default: default)
#   --skip-secrets         Skip secret creation (use existing secrets)
#   --monitor              Monitor VM startup after deployment
#   -h, --help             Show this help message
#
# Examples:
#   # Deploy with defaults
#   ./deploy.sh
#
#   # Deploy with custom SSH key
#   ./deploy.sh --ssh-key ~/.ssh/my_key.pub
#
#   # Deploy with custom userdata and manifest
#   ./deploy.sh --userdata ./my-userdata.yaml --vm-manifest ./my-vm.yaml
#
#   # Deploy and monitor startup
#   ./deploy.sh --monitor
#===============================================================================

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
USERDATA_PATH="${SCRIPT_DIR}/kali-linux-userdata.yaml"
VM_MANIFEST_PATH="${SCRIPT_DIR}/kali-linux-vdi-xrdp-gnome-br0-containerdisk.yaml"
NAMESPACE="default"
SKIP_SECRETS=false
MONITOR=false

# Secret names
SSH_SECRET_NAME="kargo-sshpubkey-kali"
USERDATA_SECRET_NAME="kali-linux-userdata"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --userdata)
            USERDATA_PATH="$2"
            shift 2
            ;;
        --vm-manifest)
            VM_MANIFEST_PATH="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-secrets)
            SKIP_SECRETS=true
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        -h|--help)
            grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate files exist
info "Validating deployment files..."

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    error "SSH key not found: $SSH_KEY_PATH"
fi

if [[ ! -f "$USERDATA_PATH" ]]; then
    error "Userdata file not found: $USERDATA_PATH"
fi

if [[ ! -f "$VM_MANIFEST_PATH" ]]; then
    error "VM manifest not found: $VM_MANIFEST_PATH"
fi

success "All required files found"

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please install kubectl first."
fi

info "Using namespace: $NAMESPACE"

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    warning "Namespace '$NAMESPACE' does not exist"
    read -p "Create namespace '$NAMESPACE'? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl create namespace "$NAMESPACE"
        success "Namespace '$NAMESPACE' created"
    else
        error "Deployment cancelled"
    fi
fi

# Create secrets if not skipped
if [[ "$SKIP_SECRETS" == false ]]; then
    info "Creating Kubernetes secrets..."

    # Create SSH key secret
    info "Creating SSH public key secret: $SSH_SECRET_NAME"
    if kubectl get secret "$SSH_SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
        warning "Secret '$SSH_SECRET_NAME' already exists"
        read -p "Delete and recreate? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete secret "$SSH_SECRET_NAME" -n "$NAMESPACE"
            kubectl create secret generic "$SSH_SECRET_NAME" \
                --from-file=key1="$SSH_KEY_PATH" \
                --namespace="$NAMESPACE"
            success "SSH secret recreated"
        else
            info "Using existing SSH secret"
        fi
    else
        kubectl create secret generic "$SSH_SECRET_NAME" \
            --from-file=key1="$SSH_KEY_PATH" \
            --namespace="$NAMESPACE"
        success "SSH secret created"
    fi

    # Create userdata secret
    info "Creating cloud-init userdata secret: $USERDATA_SECRET_NAME"
    if kubectl get secret "$USERDATA_SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
        warning "Secret '$USERDATA_SECRET_NAME' already exists"
        read -p "Delete and recreate? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete secret "$USERDATA_SECRET_NAME" -n "$NAMESPACE"
            kubectl create secret generic "$USERDATA_SECRET_NAME" \
                --from-file=userdata="$USERDATA_PATH" \
                --namespace="$NAMESPACE"
            success "Userdata secret recreated"
        else
            info "Using existing userdata secret"
        fi
    else
        kubectl create secret generic "$USERDATA_SECRET_NAME" \
            --from-file=userdata="$USERDATA_PATH" \
            --namespace="$NAMESPACE"
        success "Userdata secret created"
    fi
else
    info "Skipping secret creation (--skip-secrets specified)"
fi

# Verify network attachment definition exists
info "Verifying network attachment definition..."
if ! kubectl get net-attach-def br0-network-attachment -n "$NAMESPACE" &> /dev/null; then
    warning "Network attachment definition 'br0-network-attachment' not found in namespace '$NAMESPACE'"
    warning "The VM may fail to start without this network configuration"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Deployment cancelled"
    fi
else
    success "Network attachment definition found"
fi

# Deploy VirtualMachine
info "Deploying VirtualMachine..."
kubectl apply -f "$VM_MANIFEST_PATH" -n "$NAMESPACE"
success "VirtualMachine deployed"

# Get VM name from manifest
VM_NAME=$(kubectl get -f "$VM_MANIFEST_PATH" -n "$NAMESPACE" -o jsonpath='{.metadata.name}')
info "VirtualMachine name: $VM_NAME"

# Show deployment summary
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Deployment Summary"
echo "═══════════════════════════════════════════════════════════"
echo "  VM Name:       $VM_NAME"
echo "  Namespace:     $NAMESPACE"
echo "  SSH Key:       $SSH_KEY_PATH"
echo "  Userdata:      $USERDATA_PATH"
echo "  VM Manifest:   $VM_MANIFEST_PATH"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Monitor startup if requested
if [[ "$MONITOR" == true ]]; then
    info "Monitoring VM startup (press Ctrl+C to stop)..."
    echo ""
    info "Waiting for VirtualMachineInstance to be created..."

    # Wait for VMI to exist
    while ! kubectl get vmi "$VM_NAME" -n "$NAMESPACE" &> /dev/null; do
        sleep 2
    done
    success "VirtualMachineInstance created"

    echo ""
    info "Current status:"
    kubectl get vm,vmi,dv,pvc -n "$NAMESPACE" -l app="$VM_NAME" 2>/dev/null || \
        kubectl get vm,vmi,dv,pvc -n "$NAMESPACE" | grep -E "(NAME|$VM_NAME)"

    echo ""
    info "Waiting for VM to be running..."
    kubectl wait --for=condition=Ready vmi/"$VM_NAME" -n "$NAMESPACE" --timeout=600s 2>/dev/null || \
        warning "Timeout waiting for VM to be ready (this is normal for large images)"

    echo ""
    info "Getting VM IP address..."
    sleep 5  # Give time for IP to be assigned
    VM_IP=$(kubectl get vmi "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")

    if [[ -n "$VM_IP" ]]; then
        success "VM is running with IP: $VM_IP"
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  Connection Information"
        echo "═══════════════════════════════════════════════════════════"
        echo "  VM IP:         $VM_IP"
        echo "  SSH:           ssh kali@$VM_IP"
        echo "  RDP:           xfreerdp /v:$VM_IP:3389 /u:kali /p:kali /cert:ignore"
        echo "  Console:       virtctl console $VM_NAME -n $NAMESPACE"
        echo ""
        echo "  User:          kali"
        echo "  Password:      kali"
        echo "═══════════════════════════════════════════════════════════"
    else
        warning "Could not retrieve VM IP address"
        info "Check VM status with: kubectl get vmi $VM_NAME -n $NAMESPACE -o yaml"
    fi
else
    echo ""
    info "To monitor VM startup, run:"
    echo "  kubectl get vm,vmi,dv,pvc -n $NAMESPACE"
    echo ""
    info "To get VM IP address once running:"
    echo "  kubectl get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces[0].ipAddress}'"
    echo ""
    info "To connect to VM console:"
    echo "  virtctl console $VM_NAME -n $NAMESPACE"
fi

echo ""
success "Deployment complete!"
