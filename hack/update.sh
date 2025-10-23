#!/usr/bin/env bash

set -ex

archlinux::latest() {
	local file="images/archlinux-latest/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}" | grep cloudimg | awk -F\" '{print $2}')
	local image=$(echo ${response} | cut -d ' ' -f1)
	local amd64_sha256sum=$(curl -s "${BASE_URL}${image}.SHA256" | awk -F ' ' '{print $1}')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
}

ubuntu::24-04() {
	local file="images/ubuntu-24-04/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA256SUMS)
	local amd64_sha256sum=$(echo "${response}" | grep noble-server-cloudimg-amd64.img | awk -F ' ' '{print $1}')
	local arm64_sha256sum=$(echo "${response}" | grep noble-server-cloudimg-arm64.img | awk -F ' ' '{print $1}')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

fedora::42() {
	local file="images/fedora-42/env.sh"
	local response=$(curl -s https://getfedora.org/releases.json)
	local amd64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="x86_64" and .version=="42").sha256')
	local arm64_sha256sum=$(echo "${response}" |
		jq -r '.[] | select(.link|test(".*Generic.*qcow2")) | select(.variant=="Cloud" and .arch=="aarch64" and .version=="42").sha256')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

debian::10() {
	local file="images/debian-10/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA512SUMS)
	local amd64_sha512sum=$(echo "${response}" | grep debian-10-generic-amd64.qcow2 | awk -F ' ' '{print $1}')
	local arm64_sha512sum=$(echo "${response}" | grep debian-10-generic-arm64.qcow2 | awk -F ' ' '{print $1}')
	sed -i "s/AMD64_SHA512SUM=.*/AMD64_SHA512SUM=${amd64_sha512sum}/" "${file}"
	sed -i "s/ARM64_SHA512SUM=.*/ARM64_SHA512SUM=${arm64_sha512sum}/" "${file}"
}

debian::11() {
	local file="images/debian-11/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA512SUMS)
	local amd64_sha512sum=$(echo "${response}" | grep debian-11-generic-amd64.qcow2 | awk -F ' ' '{print $1}')
	local arm64_sha512sum=$(echo "${response}" | grep debian-11-generic-arm64.qcow2 | awk -F ' ' '{print $1}')
	sed -i "s/AMD64_SHA512SUM=.*/AMD64_SHA512SUM=${amd64_sha512sum}/" "${file}"
	sed -i "s/ARM64_SHA512SUM=.*/ARM64_SHA512SUM=${arm64_sha512sum}/" "${file}"
}

debian::13() {
	local file="images/debian-13/env.sh"
	source "${file}"
	local response=$(curl -s "${BASE_URL}"/SHA512SUMS)
	local amd64_sha512sum=$(echo "${response}" | grep debian-13-generic-amd64.qcow2 | awk -F ' ' '{print $1}')
	local arm64_sha512sum=$(echo "${response}" | grep debian-13-generic-arm64.qcow2 | awk -F ' ' '{print $1}')
	sed -i "s/AMD64_SHA512SUM=.*/AMD64_SHA512SUM=${amd64_sha512sum}/" "${file}"
	sed -i "s/ARM64_SHA512SUM=.*/ARM64_SHA512SUM=${arm64_sha512sum}/" "${file}"
}

centos::8() {
	local file="images/centos-8/env.sh"
	local new_build=$(curl -s https://cloud.centos.org/centos/8-stream/x86_64/images/CHECKSUM \
		| grep 'qcow2' | grep -wo '2021.*.0' | sort | head -n 1)
	local amd64_sha256sum=$(curl -s https://cloud.centos.org/centos/8-stream/x86_64/images/CHECKSUM \
		| grep "GenericCloud-8-${new_build}.x86_64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	local arm64_sha256sum=$(curl -s https://cloud.centos.org/centos/8-stream/aarch64/images/CHECKSUM \
		| grep "GenericCloud-8-${new_build}.aarch64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	sed -i "s/_BUILD_DATE=.*/_BUILD_DATE=${new_build}/" "${file}"
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

centos::9() {
	local file="images/centos-9/env.sh"
	local new_build=$(curl -s https://cloud.centos.org/centos/9-stream/x86_64/images/CHECKSUM \
		| grep 'qcow2' | grep -wo '2022.*.0' | sort | head -n 1)
	local amd64_sha256sum=$(curl -s https://cloud.centos.org/centos/9-stream/x86_64/images/CHECKSUM \
		| grep "GenericCloud-9-${new_build}.x86_64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	local arm64_sha256sum=$(curl -s https://cloud.centos.org/centos/9-stream/aarch64/images/CHECKSUM \
		| grep "GenericCloud-9-${new_build}.aarch64.qcow2" | awk -F' = ' '{print $2}' | tr -d "\n")
	sed -i "s/_BUILD_DATE=.*/_BUILD_DATE=${new_build}/" "${file}"
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

rocky::8() {
	local file="images/rocky-8/env.sh"
	source "${file}"
	local response=$(curl -s ${BASE_URL}/CHECKSUM)
	local amd64_build=$(echo "${response}" | grep x86_64 | awk -F' = ' '{print $1}' | awk -F'[()]' '{print $2}')
	local arm64_build=$(echo "${response}" | grep aarch64 | awk -F' = ' '{print $1}' | awk -F'[()]' '{print $2}')
	local amd64_sha256sum=$(echo "${response}" | grep x86_64 | awk -F' = ' '{print $2}')
	local arm64_sha256sum=$(echo "${response}" | grep aarch64 | awk -F' = ' '{print $2}')
	sed -i "s/AMD64_DOWNLOAD_FILE=.*/AMD64_DOWNLOAD_FILE=${amd64_build}/" "${file}"
	sed -i "s/ARM64_DOWNLOAD_FILE=.*/ARM64_DOWNLOAD_FILE=${arm64_build}/" "${file}"
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

almalinux::10() {
	local file="images/almalinux-10/env.sh"
	local amd64_sha256sum=$(curl -s https://repo.almalinux.org/almalinux/10/cloud/x86_64_v2/images/CHECKSUM \
		| grep GenericCloud-latest | awk -F' ' '{print $1}')
	local arm64_sha256sum=$(curl -s https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/CHECKSUM \
		| grep GenericCloud-latest | awk -F' ' '{print $1}')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

opensuse::leap-16() {
	local file="images/opensuse-leap-16/env.sh"
	local amd64_sha256sum=$(curl -s https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-kvm-and-xen.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	local arm64_sha256sum=$(curl -s https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.aarch64-kvm.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

opensuse::tumbleweed() {
	local file="images/opensuse-tumbleweed/env.sh"
	local amd64_sha256sum=$(curl -s https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-kvm-and-xen.qcow2.sha256 \
		| awk -F' ' '{print $1}')
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
}

fcos::42() {
	local file="images/fcos-42/env.sh"
	local latest_build=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/builds.json \
		| jq -r '.builds[] | select(.id | startswith("42.")) | .id' | head -n 1)
	local amd64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/x86_64/meta.json \
		| jq -r '.images.qemu.sha256')
	local arm64_sha256sum=$(curl -s https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${latest_build}/aarch64/meta.json \
		| jq -r '.images.qemu.sha256')
	sed -i "s/_BUILD_VERSION=.*/_BUILD_VERSION=\"${latest_build}\"/" "${file}"
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

openwrt::24() {
	local file="images/openwrt-24/env.sh"
	local latest_version=$(curl -s https://downloads.openwrt.org/releases/ \
		| grep -oP 'href="24\.[0-9]+\.[0-9]+/"' | sed 's/href="//;s/\///' | sort -V | tail -n 1)
	local amd64_sha256sum=$(curl -s https://downloads.openwrt.org/releases/${latest_version}/targets/x86/64/sha256sums \
		| grep generic-squashfs-combined-efi.img.gz | awk '{print $1}')
	local arm64_sha256sum=$(curl -s https://downloads.openwrt.org/releases/${latest_version}/targets/armsr/armv8/sha256sums \
		| grep generic-squashfs-combined-efi.img.gz | awk '{print $1}')
	sed -i "s/__VERSION=.*/__VERSION=\"${latest_version}\"/" "${file}"
	sed -i "s/AMD64_SHA256SUM=.*/AMD64_SHA256SUM=${amd64_sha256sum}/" "${file}"
	sed -i "s/ARM64_SHA256SUM=.*/ARM64_SHA256SUM=${arm64_sha256sum}/" "${file}"
}

archlinux::latest
ubuntu::24-04
fedora::42
debian::10
debian::11
debian::13
centos::8
#centos::9
rocky::8
almalinux::10
opensuse::leap-16
opensuse::tumbleweed
fcos::42
openwrt::24
