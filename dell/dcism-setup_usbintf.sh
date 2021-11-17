#!/bin/bash
#-------------------------------------------------------------------------
#
#          DELL COMPUTER CORPORATION PROPRIETARY INFORMATION
#
#  This software is supplied under the terms of a license agreement or
#  nondisclosure agreement with Dell Computer Corporation and may not
#  be copied or disclosed except in accordance with the terms of that
#  agreement.
#
#  Copyright (c) 2013 Dell Computer Corp. All Rights Reserved.
#
#  Abstract/Purpose:
#  iSM OSBMC over usb Configuration script
#  This script detects the DELL USBNIC interface and trying to configure
#  the same using IPv4 Network, it is assumed that the consumer is
#  passing an IPv4 iDRAC USBNIC address for this script to configure the
#  host interface.
#------------------------------------------------------------------------

set -u

declare -r UNIQUE_DEVICE_ID="413c:a102"
declare -r REDHAT_RELEASE_FILE="/etc/redhat-release"
declare -r OS_RELEASE_FILE="/etc/os-release"


# On bare-metal installations, USB network devices will have sysfs
# nodes including a 'net' directory containing a single directory named
# for the network interface assigned to the device, such as 'eth0'.
#
# However, in Docker the 'net' directory exists, but is empty.
#
# Enabling host networking *may* affect this, otherwise an interface
# can be moved into the container namespace - see [1].
#
# [1]: https://stackoverflow.com/a/60564074


# This seems to be a much cleaner approach to finding the Dell USB interface...
getUSBintfName() {
	local interface identifier

	[[ -d /sys/class/net ]] || return 1

	for interface in /sys/class/net/*; do
		if [[ -s "${interface}/device/../idVendor" ]]; then
			identifier="$( < "${interface}/device/../idVendor" ):$( < "${interface}/device/../idProduct" )"
			if [[ "${identifier}" == "${UNIQUE_DEVICE_ID}" ]]; then
				basename "${interface}"
				return 0
			fi
		fi
	done

	return 1
} # getUSBintfName

AddIpToInterface() {
	interface_name="${1:-}"
	ip_addr="${2:-}"

	[[ -n "${interface_name:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'interface_name' value" ; return 1 ; }
	[[ -n "${ip_addr:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'ip_addr' value" ; return 1 ; }

	local -i intf_retcode=1

	if [[ -x /sbin/ifconfig ]]; then
		/sbin/ifconfig "${interface_name}" "${ip_addr}"
		intf_retcode=${?}
	fi 

	return $intf_retcode
} # AddIpToInterface

XenConfiguration() {
	local interface_name="${1:-}"

	[[ -n "${interface_name:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'interface_name' value" ; return 1 ; }

	local if_uuid
	local -i verify_retcode=1

	# For XenServer, remove guest bridge
	if [[ -f "${REDHAT_RELEASE_FILE}" ]] && grep -q 'XenServer' "${REDHAT_RELEASE_FILE}"; then
		:
	elif [[ -f "${OS_RELEASE_FILE}" ]] && grep -q 'XenServer' "${OS_RELEASE_FILE}"; then
		:
	else
		return 1
	fi

	if_uuid="$( xe pif-list device="${interface_name}" | grep 'uuid' | grep -v 'network-uuid' | cut -d ":" -f 2 | cut -d " " -f 2 )"

	if [[ -n "${if_uuid:-}" ]]; then
		xe pif-forget uuid="${if_uuid}"
		verify_retcode=0
	fi

	return ${verify_retcode}
} # XenConfiguration

VerifyDestinationIP() {
	destination_ip="${1:-}"
	interface_name="${2:-}"

	[[ -n "${destination_ip:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'destination_ip' value" ; return 1 ; }
	[[ -n "${interface_name:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'interface_name' value" ; return 1 ; }

	local -i verify_retcode=1

	XenConfiguration "${interface_name}" || true

	if ping -c 5 -I "${interface_name}" "${destination_ip}" >/dev/null && ping -c 5 "${destination_ip}" > /dev/null; then
		verify_retcode=0
	fi

	return "${verify_retcode}"
} # VerifyDestinationIP

VerifyDestinationRoute() {
	destination_ip="${1:-}"
	source_ip="${2:-}"

	[[ -n "${destination_ip:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'destination_ip' value" ; return 1 ; }
	[[ -n "${source_ip:-}" ]] || { echo >&2 "WARN: ${FUNCNAME[0]} received no 'source_ip' value" ; return 1 ; }

	local -i verify_retcode=1

	echo "VerifyDestinationRoute called with destination IP '${destination_ip}' and source IP '${source_ip}'"

	if ping -c 1 -R "${destination_ip}" | grep -Fq "${source_ip}"; then
		# Route is fine
		verify_retcode=0
	fi

	return ${verify_retcode}
} # VerifyDestinationRoute

# It looks as if the first parameter is intended to be '1' or anything else,
# and if the former then the interface name is discovered and output, and then
# the script exits successfully on RedHat or CentOS, but fails on Ubuntu(?)
#
# Otherwise, the second parameter is an IP address to assign to the iDRAC USB
# network interface.

# Start of script...
declare -i retcode=1

command="${1:-}"
DESTINATION_IP="${2:-}"

if ! lsusb | grep -qi "${UNIQUE_DEVICE_ID}"; then
	echo "Dell USBNIC Device is not exposed or OS driver for usbnic is not loaded"
	exit ${retcode}
fi

interfacename="$( getUSBintfName )"

# This is to get usbnic interface name
if [[ "${command:-}" = '1' ]]; then
	XenConfiguration "${interfacename}"
	echo "${interfacename}"

	if [[ -f "${REDHAT_RELEASE_FILE}" ]] && grep -q '7.0\|CentOS' "${REDHAT_RELEASE_FILE}"; then
		:
	elif [[ -f "${OS_RELEASE_FILE}" ]] && grep -q '7.0\|CentOS' "${OS_RELEASE_FILE}"; then
		:
	else
		exit 1
	fi

	exit 0
fi

echo "Dell USBNIC is exposed on interface ${interfacename}"

[[ -n "${DESTINATION_IP:-}" ]] || exit 0

if VerifyDestinationIP "${DESTINATION_IP}" "${interfacename}"; then
	# Get the exiting address as ping is working
	if /sbin/ifconfig "${interfacename}" | grep 'inet ' | grep -q ':'; then
		existing_source_ip="$( /sbin/ifconfig "${interfacename}" | grep 'inet addr:' | cut -d ':' -f 2 | cut -d ' ' -f 1 )"
	else
		# RHEL 7 case
		existing_source_ip="$( /sbin/ifconfig "${interfacename}" | grep 'inet ' | cut -d 'i' -f 2 | cut -d ' ' -f 2 )"
	fi
	echo "existing_source_ip = ${existing_source_ip}"

	if VerifyDestinationRoute "${DESTINATION_IP}" "${existing_source_ip}"; then
		echo "USB pass-through is working"
		retcode=0
	else
		echo "USB pass-through is working, but intended route not configured"
		retcode=2
	fi
else
	echo "Configuring USB pass-through ..."

	# Parse detination IP
	source_ip_octet1="$( cut -d "." -f 1 <<<"${DESTINATION_IP}" )"
	source_ip_octet2="$( cut -d "." -f 2 <<<"${DESTINATION_IP}" )"
	source_ip_octet3="$( cut -d "." -f 3 <<<"${DESTINATION_IP}" )"
	source_ip_octet4="$( cut -d "." -f 4 <<<"${DESTINATION_IP}" )"

	if (( source_ip_octet4 > 253 )); then
		(( source_ip_octet4 -- ))
	else
		(( source_ip_octet4 ++ ))
	fi

	SOURCE_IP="${source_ip_octet1}.${source_ip_octet2}.${source_ip_octet3}.${source_ip_octet4}"

	echo "DESTINATION_IP=${DESTINATION_IP}"
	echo "SOURCE_IP=${SOURCE_IP}"

	if \
		AddIpToInterface "${interfacename}" "${SOURCE_IP}" && \
		VerifyDestinationIP "${DESTINATION_IP}" "${interfacename}" && \
		VerifyDestinationRoute "${DESTINATION_IP}" "${SOURCE_IP}"
	then
		echo "Setup complete"
		retcode=0
	else
		echo "USB pass-through is working, but intended route not found"
		retcode=2
	fi
fi

exit ${retcode}

# vi: set syntax=sh colorcolumn=80:
