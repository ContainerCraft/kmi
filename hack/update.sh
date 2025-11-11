#!/usr/bin/env bash

set -ex

# Platform-independent sed -i function
sedi() {
	if [[ "$OSTYPE" == "darwin"* ]]; then
		sed -i '' "$@"
	else
		sed -i "$@"
	fi
}

archlinux::latest() {
	local file="images/archlinux-latest/env.sh"
	local amd64_sha256sum=$(curl -Ls https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256 \
		| awk -F' ' '{print $1}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
}

ubuntu::24-04() {
	set +x  # Disable xtrace to avoid printing massive SHA256SUMS
	local file="images/ubuntu-24-04/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA256SUMS)
	local amd64_sha256sum=$(echo "${response}" | grep noble-server-cloudimg-amd64.img | awk -F ' ' '{print $1}')
	local arm64_sha256sum=$(echo "${response}" | grep noble-server-cloudimg-arm64.img | awk -F ' ' '{print $1}')
	set -x  # Re-enable xtrace
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

ubuntu::25-10() {
	set +x  # Disable xtrace to avoid printing massive SHA256SUMS
	local file="images/ubuntu-25-10/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA256SUMS)
	local amd64_sha256sum=$(echo "${response}" | grep questing-server-cloudimg-amd64.img | awk -F ' ' '{print $1}')
	local arm64_sha256sum=$(echo "${response}" | grep questing-server-cloudimg-arm64.img | awk -F ' ' '{print $1}')
	set -x  # Re-enable xtrace
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

fedora::42() {
	set +x  # Disable xtrace to avoid printing massive JSON
	local file="images/fedora-42/env.sh"
	local response=$(curl -sL https://fedoraproject.org/releases.json)
	local amd64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="x86_64" and .version=="42").sha256')
	local arm64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="aarch64" and .version=="42").sha256')
	set -x  # Re-enable xtrace
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

fedora::43() {
	set +x  # Disable xtrace to avoid printing massive JSON
	local file="images/fedora-43/env.sh"
	local response=$(curl -sL https://fedoraproject.org/releases.json)
	local amd64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="x86_64" and .version=="43").sha256')
	local arm64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="aarch64" and .version=="43").sha256')
	set -x  # Re-enable xtrace
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

debian::13() {
	set +x  # Disable xtrace to avoid printing massive SHA512SUMS
	local file="images/debian-13/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA512SUMS)
	local amd64_sha512sum=$(echo "${response}" | grep debian-13-generic-amd64.qcow2 | awk -F ' ' '{print $1}')
	local arm64_sha512sum=$(echo "${response}" | grep debian-13-generic-arm64.qcow2 | awk -F ' ' '{print $1}')
	set -x  # Re-enable xtrace
	sedi "s/AMD64_SHA512SUM=.*/AMD64_SHA512SUM=${amd64_sha512sum}/" "${file}"
	sedi "s/ARM64_SHA512SUM=.*/ARM64_SHA512SUM=${arm64_sha512sum}/" "${file}"
}

centos::10() {
	local file="images/centos-10/env.sh"
	local new_build=$(curl -s https://cloud.centos.org/centos/10-stream/x86_64/images/CHECKSUM \
		| grep 'qcow2' | grep -wo '2025.*.0' | sort | head -n 1)
	local amd64_sha256sum=$(curl -s https://cloud.centos.org/centos/10-stream/x86_64/images/CHECKSUM \
		| grep "GenericCloud-10-${new_build}.x86_64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	local arm64_sha256sum=$(curl -s https://cloud.centos.org/centos/10-stream/aarch64/images/CHECKSUM \
		| grep "GenericCloud-10-${new_build}.aarch64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	sedi "s/_BUILD_DATE=.*/_BUILD_DATE=${new_build}/" "${file}"
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

rocky::10() {
	local file="images/rocky-10/env.sh"
	local amd64_sha256sum=$(curl -Ls https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM \
		| grep SHA256 | awk -F' = ' '{print $2}')
	local arm64_sha256sum=$(curl -Ls https://download.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2.CHECKSUM \
		| grep SHA256 | awk -F' = ' '{print $2}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

almalinux::10() {
	local file="images/almalinux-10/env.sh"
	local amd64_sha256sum=$(curl -s https://repo.almalinux.org/almalinux/10/cloud/x86_64_v2/images/CHECKSUM \
		| grep GenericCloud-latest | awk -F' ' '{print $1}')
	local arm64_sha256sum=$(curl -s https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/CHECKSUM \
		| grep GenericCloud-latest | awk -F' ' '{print $1}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

opensuse::leap-16() {
	local file="images/opensuse-leap-16/env.sh"
	local amd64_sha256sum=$(curl -s https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-kvm-and-xen.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	local arm64_sha256sum=$(curl -s https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.aarch64-kvm.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

opensuse::tumbleweed() {
	local file="images/opensuse-tumbleweed/env.sh"
	local amd64_sha256sum=$(curl -s https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-kvm-and-xen.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
}

fcos::42() {
	local file="images/fcos-42/env.sh"
	local latest_build=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/builds.json \
		| jq -r '.builds[] | select(.id | startswith("42.")) | .id' | head -n 1)
	local amd64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/x86_64/meta.json \
		| jq -r '.images.qemu.sha256')
	local arm64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/aarch64/meta.json \
		| jq -r '.images.qemu.sha256')
	sedi "s/_BUILD_VERSION=.*/_BUILD_VERSION=\"${latest_build}\"/" "${file}"
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

fcos::43() {
	local file="images/fcos-43/env.sh"
	local latest_build=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/builds.json \
		| jq -r '.builds[] | select(.id | startswith("43.")) | .id' | head -n 1)
	local amd64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/x86_64/meta.json \
		| jq -r '.images.qemu.sha256')
	local arm64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/aarch64/meta.json \
		| jq -r '.images.qemu.sha256')
	sedi "s/_BUILD_VERSION=.*/_BUILD_VERSION=\"${latest_build}\"/" "${file}"
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

openwrt::24() {
	local file="images/openwrt-24/env.sh"
	local latest_version=$(curl -s https://downloads.openwrt.org/releases/ \
		| sed -n 's/.*href="\(24\.[0-9][0-9]*\.[0-9][0-9]*\)\/".*/\1/p' | sort -V | tail -n 1)
	local amd64_sha256sum=$(curl -s https://downloads.openwrt.org/releases/${latest_version}/targets/x86/64/sha256sums \
		| grep generic-squashfs-combined-efi.img.gz | awk '{print $1}')
	local arm64_sha256sum=$(curl -s https://downloads.openwrt.org/releases/${latest_version}/targets/armsr/armv8/sha256sums \
		| grep generic-squashfs-combined-efi.img.gz | awk '{print $1}')
	sedi "s/__VERSION=.*/__VERSION=\"${latest_version}\"/" "${file}"
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sedi "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

freebsd::15() {
	local file="images/freebsd-15/env.sh"
	local amd64_sha256sum=$(curl -Ls https://download.freebsd.org/releases/VM-IMAGES/15.0-BETA5/amd64/Latest/CHECKSUM.SHA256 \
		| grep 'FreeBSD-15.0-BETA5-amd64-zfs.qcow2.xz' | awk '{print $NF}')
	sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	# ARM64 checksums not available for BETA5, skip for now
}

talos::1-11() {
	# Talos uses Image Factory with specific schematic IDs
	# Auto-update not implemented - checksums change per build with schematic
	echo "Talos 1.11 builds from Image Factory - no automatic updates available"
	echo "Check https://factory.talos.dev/ for latest Talos releases"
}

vyos::rolling() {
	# VyOS rolling builds from source using vyos-build container
	# No checksums to update - images are built from git 'current' branch
	# Rolling release contains latest development code
	# Stream and LTS require subscription/authentication
	# See: https://vyos.io/get/ for more information
	echo "VyOS rolling builds from source - no automatic updates available"
	echo "Check https://vyos.io/get/ for latest VyOS releases"
}

kali::linux() {
	local file="images/kali-linux/env.sh"
	source "${file}"
	# Fetch current version by parsing the latest QEMU image filename from SHA256SUMS
	local latest_file=$(curl -s https://mirror.fcix.net/kali-images/current/SHA256SUMS \
		| grep 'qemu-amd64.7z$' | grep -v '.torrent' | awk '{print $2}')
	local latest_version=$(echo "${latest_file}" | sed -n 's/kali-linux-\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
	local amd64_sha256sum=$(curl -s https://mirror.fcix.net/kali-images/current/SHA256SUMS \
		| grep "${latest_file}" | grep -v 'torrent' | awk '{print $1}')

	if [[ -n "${latest_version}" ]] && [[ -n "${amd64_sha256sum}" ]]; then
		sedi "s/__VERSION=.*/__VERSION=\"${latest_version}\"/" "${file}"
		sedi "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
		echo "Updated Kali Linux to version ${latest_version}"
	else
		echo "Warning: Could not fetch Kali Linux version or checksum"
	fi
}

archlinux::latest
ubuntu::24-04
ubuntu::25-10
fedora::42
fedora::43
debian::13
centos::10
rocky::10
almalinux::10
opensuse::leap-16
opensuse::tumbleweed
fcos::42
fcos::43
openwrt::24
freebsd::15
talos::1-11
vyos::rolling
kali::linux
