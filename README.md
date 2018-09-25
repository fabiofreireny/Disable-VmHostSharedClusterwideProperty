# Disable-VmHostSharedClusterwideProperty
In ESX, changes "shared-clusterwide" property of LUNS of a specific size

When an ESX has its boot volume on shared storage, VMware assumes it's supposed to be shared and flags it as such.
When using Host Profiles this creates a compliance failure as the boot volume is never shared.
The resolution is to flag each boot volume (in each host) as non-shared.

If your boot volumes aren't all the same size you may need to experiment with some other characteristic of your hosts. I also ran across a couple of volumes that weren't boot but were the same size. In that case the script will prompt you.

The framework for connecting, running a command, then disconnecting is pretty straightforward. You may want to use it for other situations when you need to SHH onto an ESX host.

The resolution to this issue came from : http://www.yellow-bricks.com/2015/03/19/host-profile-noncompliant-when-using-local-sas-drives-with-vsphere-6/