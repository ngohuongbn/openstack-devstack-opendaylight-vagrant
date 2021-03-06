#!/usr/bin/env bash

set -x
set -e errexit
# set -o pipefail

dnf upgrade -y

dnf install -y nano git qemu-kvm libvirt-client
# Ensure that hardware accelerated nested virtualization works
cat /proc/cpuinfo | grep vmx
/sbin/lsmod | grep kvm
# Due to set -e above, this simple ls will fail if there is no nested virtualization:
ls /dev/kvm
# Fails even if it's just a WARN for "QEMU: Checking for device assignment IOMMU support" :-(
# virt-host-validate

# Disable SELinux on next reboot
echo "SELINUX=disabled" >/etc/selinux/config
echo "SELINUXTYPE=targeted" >>/etc/selinux/config
# Disable SELinux right now
setenforce 0
getenforce

# Fedora Cloud does not seem to have firewalld & iptables on by default anyway
# systemctl stop    firewalld
# systemctl disable firewalld
# Even if iptables gets enabled by stack.sh (but does it?), it's best to have explicit ACCEPT after stack, below, instead of stop/disable
# systemctl stop    iptables.service
# systemctl disable iptables.service

git clone https://git.openstack.org/openstack-dev/devstack
cd devstack
git checkout stable/newton
cp samples/local.conf local.conf

# This script creates a new ~stack user
./tools/create-stack-user.sh

# Huh? Sometimes it seems to use /opt/logs/stack and sometimes /opt/stack/logs/ ?!
mkdir -p /opt/logs/stack
chmod 777 /opt/logs/stack
mkdir -p /opt/stack/logs/
chmod 777 /opt/stack/logs/

# New user has home directory in /opt/stack (not /home), which script created
# so we move our devstack git clone there from the PWD, and fix permissions
mkdir /opt/stack/devstack/
mv {.[!.],}* /opt/stack/devstack/
cd ..
rmdir devstack

cp /vagrant/local.conf /opt/stack/devstack/local.conf

# This prevents a problem with "tempest", see https://gist.github.com/vorburger/3d08800f68672b7b483d43aeb774055b
# TODO How to do this "later" ?!?
## pip uninstall -y appdirs

# Add some useful utilities
# TODO align directory locations between this project and these scripts.. (they assume /opt/devstack while we're in /opt/stack/devstack/)
## sudo su - stack -c 'cd ~stack; git clone https://github.com/shague/odl_tools.git'

# Now run stack.sh, but as our new user (~stack), not as the currently running ~root
sudo chown -R stack:stack /opt/stack/devstack/
sudo su - stack -c 'cd ~stack/devstack && ./stack.sh'

# stack turns on iptables, so allow some ports (6080 = novnc)
sudo iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 6080 -j ACCEPT

# When we're done, go to offline and no reclone, for faster future ./stack.sh after VM restart
sed -i -r -e 's/^#*\s*(OFFLINE=).*$/\1True/' /opt/stack/devstack/local.conf
sed -i -r -e 's/^#*\s*(RECLONE=).*$/\1False/' /opt/stack/devstack/local.conf

