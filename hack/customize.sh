#!/usr/bin/env bash
# Requires libguestfs-tools and curl

FLAVOR=${FLAVOR:-$1}
ARCH=${ARCH:-$2}

if [[ -z ${FLAVOR} ]] || [[ -z ${ARCH} ]]; then
	echo "Error: \$FLAVOR and \$ARCH must be passed in"
	exit 1
fi

set -ex

# Disable libvirtd layer
# Required to support edge cases for some distributions
export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_CACHEDIR=${HOME}

QCOW2_FILE=${FLAVOR}-${ARCH}.qcow2
QCOW2_TMPFILE=tmp.${FLAVOR}-${ARCH}.qcow2

# Source OS build variables
BASE_URL=
DOWNLOAD_FILE=
SHASUM="${ARCH^^}_SHA256SUM"
CUSTOMIZE=true
VIRT_SYSPREP_OPERATIONS=

# shellcheck disable=SC1090
source images/"${FLAVOR}"/env.sh

SUMMER=sha256sum
if [[ -z "${!SHASUM}" ]]; then
	SHASUM="${ARCH^^}_SHA512SUM"
	SUMMER=sha512sum
fi

if [[ -z "${DOWNLOAD_FILE}" ]]; then
	__DL_FILE="${ARCH^^}_DOWNLOAD_FILE"
	DOWNLOAD_FILE="${!__DL_FILE}"
fi

if [[ -z "${BASE_URL}" ]]; then
	__BASE_URL="${ARCH^^}_BASE_URL"
	BASE_URL="${!__BASE_URL}"
fi

# Download qcow2
curl \
	--fail \
	--verbose \
	--output "${DOWNLOAD_FILE}" \
	--location "${BASE_URL}"/"${DOWNLOAD_FILE}"

# Verify Checksum (skip if checksum not provided, e.g. for beta releases)
if [[ -n "${!SHASUM}" ]]; then
	echo "${!SHASUM} ${DOWNLOAD_FILE}" |
		${SUMMER} --check --status ||
		(echo "Invalid checksum: ${SUMMER} check failed" && exit 1)
else
	echo "Warning: Checksum validation skipped (no checksum provided for ${ARCH})"
fi

# Unarchive image
if [[ "${DOWNLOAD_FILE}" =~ \.gz$ ]]; then
	# TODO(jbpratt): OpenWrt compressed image contains additional garbage that
	# causes a warning (exit code 2) to be returned though the decompression
	# succeeds. This probably isn't the best fix...
	# https://lists.openwrt.org/pipermail/openwrt-devel/2020-April/028777.html
	gzip -d "${DOWNLOAD_FILE}" || :
	mv "${DOWNLOAD_FILE/.gz/}" "${QCOW2_TMPFILE}"
elif [[ "${DOWNLOAD_FILE}" =~ \.xz$ ]]; then
	unxz "${DOWNLOAD_FILE}"
	mv "${DOWNLOAD_FILE/.xz/}" "${QCOW2_TMPFILE}"
else
	mv "${DOWNLOAD_FILE}" "${QCOW2_TMPFILE}"
fi

if [[ "${CONVERT}" == "true" ]]; then
	qemu-img convert "${QCOW2_TMPFILE}" -O qcow2 converted."${QCOW2_TMPFILE}"
	mv converted."${QCOW2_TMPFILE}" "${QCOW2_TMPFILE}"
fi

if [[ "${CUSTOMIZE}" == "true" ]]; then
	# Grow disk size
	qemu-img resize "${QCOW2_TMPFILE}" +20G

	# Pre-Sparsify
	sudo virt-sparsify \
		--verbose \
		--inplace \
		"${QCOW2_TMPFILE}"

	# Customize Disk Image
	sudo virt-sysprep \
		--verbose \
		--network \
		--add "${QCOW2_TMPFILE}" \
		--commands-from-file images/"${FLAVOR}"/virt.sysprep \
		--enable "${VIRT_SYSPREP_OPERATIONS}"

	# Log disk image info
	qemu-img info "${QCOW2_TMPFILE}"

	# Post-Sparsify
	sudo virt-sparsify \
		--verbose \
		--compress \
		"${QCOW2_TMPFILE}" \
		"${QCOW2_FILE}"
else
	mv "${QCOW2_TMPFILE}" "${QCOW2_FILE}"
fi

sudo chown "${USER}":"${USER}" "${QCOW2_FILE}" && sudo rm -f "${QCOW2_TMPFILE}"
