#!/bin/bash
set -ex

FLAVOR=${1:-ubuntu-24-04}
ARCH=${2:-amd64}

# Build qcow2 image using hack/customize.sh (just like CircleCI)
cd ..
bash hack/customize.sh ${FLAVOR} ${ARCH}
cd poc
cp ../images/${FLAVOR}-${ARCH}.qcow2 ./disk.qcow2

# Generate cloud-init ISO
cloud-localds seed.iso user-data meta-data

# Launch VM
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -m 2048 \
  -smp 2 \
  -drive file=disk.qcow2,format=qcow2,if=virtio \
  -drive file=seed.iso,format=raw,if=virtio \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -chardev socket,path=qga.sock,server=on,wait=off,id=qga0 \
  -device virtio-serial \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -nographic \
  -daemonize \
  -pidfile vm.pid

# Wait for qemu-guest-agent
for i in {1..60}; do
  echo '{"execute":"guest-ping"}' | socat - UNIX:qga.sock 2>/dev/null && break
  sleep 2
done

# Wait for SSH
for i in {1..30}; do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i id_rsa -p 2222 test@localhost whoami && break
  sleep 2
done

# Run tests
ssh -o StrictHostKeyChecking=no -i id_rsa -p 2222 test@localhost "cloud-init status --wait"
ssh -o StrictHostKeyChecking=no -i id_rsa -p 2222 test@localhost "df -h /"

echo " Tests passed"

# Cleanup
kill $(cat vm.pid)
rm -f disk.qcow2 seed.iso qga.sock vm.pid
