#! /bin/sh

set -eu

ubuntu() {
	/usr/sbin/nscd
	/lib/systemd/systemd-udevd -d

	udevadm control --start-exec-queue
	udevadm trigger
	udevadm settle

	export PATH="${PATH}:/opt/dell/srvadmin/iSM/sbin:/opt/dell/srvadmin/iSM/bin"

	/opt/dell/srvadmin/iSM/sbin/dcism-setup_usbintf.sh || true

	/opt/dell/srvadmin/iSM/sbin/dsm_ism_srvmgrd

	#exec inotifywait -q -e close -e delete_self /opt/dell/srvadmin/iSM/var/run/openmanage/dsm_ism_srvmgrd.pid
	#
	# Just in case dsm_ism_srvmgrd doesn't remove its PID file on exit...
	exec inotifywait -q -e delete -e delete_self "/proc/$( < /opt/dell/srvadmin/iSM/var/run/openmanage/dsm_ism_srvmgrd.pid )"
} # ubuntu

centos() {
	exec dsu -n -p
} # centos

if [ -e /etc/lsb-release ]; then
	if grep -Fq 'DISTRIB_ID=Ubuntu' /etc/lsb-release; then
		ubuntu
	fi
fi

centos

# vi: set colorcolumn=80:
