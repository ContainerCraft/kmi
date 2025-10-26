#!/bin/bash
set -e

NAMESPACE="${NAMESPACE:-default}"
VM_NAME="vyos-basic"
SECRET_NAME="vyos-basic-config"

echo "Deploying VyOS Basic Router to namespace: ${NAMESPACE}"

# Create NetworkAttachmentDefinitions
echo "Creating NetworkAttachmentDefinitions..."
kubectl apply -n "${NAMESPACE}" -f net-attach-def-wan-br1.yaml
kubectl apply -n "${NAMESPACE}" -f net-attach-def-lan-br0.yaml

# Create or update the cloud-init secret
echo "Creating cloud-init secret..."
kubectl delete secret -n "${NAMESPACE}" "${SECRET_NAME}" --ignore-not-found
kubectl create secret generic "${SECRET_NAME}" \
  -n "${NAMESPACE}" \
  --from-file=userdata=cloud-config.userdata

# Deploy the VirtualMachine
echo "Deploying VirtualMachine..."
kubectl delete vm -n "${NAMESPACE}" "${VM_NAME}" --ignore-not-found
kubectl apply -n "${NAMESPACE}" -f vyos-vm.yaml

# Wait for VM to be ready
echo "Waiting for VM to become ready..."
kubectl wait -n "${NAMESPACE}" --for=condition=Ready vm/"${VM_NAME}" --timeout=300s || true

# Show VM status
echo ""
echo "Deployment complete. VM status:"
kubectl get -n "${NAMESPACE}" vm,vmi "${VM_NAME}"

# Show how to connect
echo ""
echo "To connect to the VyOS router:"
echo "  virtctl console -n ${NAMESPACE} ${VM_NAME}"
echo ""
echo "Or via SSH (once network is configured):"
echo "  ssh -p 2222 vyos@<vm-ip>"
echo ""
echo "Default credentials: vyos / vyos (if password auth not disabled)"
echo "SSH key authentication is configured for the provided public key"