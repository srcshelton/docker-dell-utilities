Dell OMSA on CentOS
===================

Deploy the Dell/EMC OpenManage Server Administrator tools into a Docker
container and run DSU (Dell System Update) when executed.

Dell ISM on Ubuntu
==================

Deploy the Dell/EMC iDRAC Service Module into a Docker container and run the
ISM when executed.

Notes
=====

The following kernel modules are used by the ISM:

```
dcdbas
dell_rbu
ipmi_devintf
```

Licences
========

Included is `dcism-setup_usbintf.sh` - a rewrite of the largely-broken script
provided by Dell themselves.  The licence under which the original script is
distributed is unclear from both its contents and the installation procedure
which created it. Any licence text distributed with this repository does not,
therefore, apply to this file.

Known issues
============

 * The linux kernel doesn't virtualise the sysctl interface, which is the only
   method docker provides to control use of IPv6 if supported by the host
   system but not docker itself. This means that one of three unpalatable
   options are faced:

   1. Allow docker to apply sysctl changes and all containers work (without
      IPv6) but the host system loses IPv6 connectivity whenever the container
      is started;
   2. Make no changes, and if the container receives an IPv6 response faster
      than IPv4 when installing packages, it will hang or fail;
   3. Configure the docker daemon for IPv6 support which - as of release
      19.03 - is still non-default, awkward, and brings other limitations.

 * The DSU process has not been thoroughly explored to ensure that all required
   setup and dependencies are initialised;

 * The ISM binary appears to be operating as expected from the OS level, but
   the iDRAC system itself reports that the ISM disconnects shortly after
   launch.

