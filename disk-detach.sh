#!/bin/bash

declare -a  WORKERS
for worker in $(virsh list --all --name | grep ${CLUSTER_NAME} | grep worker) ; do
        WORKERS+=("${worker}")
done

for worker in ${WORKERS[@]} ; do
        virsh -c qemu:///system detach-disk "${worker}" --persistent --target vdb
        virsh -c qemu:///system detach-disk "${worker}" --persistent --target vdc
        virsh -c qemu:///system detach-disk "${worker}" --persistent --target vdd
        sudo rm -f /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-1.qcow2
        sudo rm -f /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-2.qcow2
        sudo rm -f /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-3.qcow2
done

echo $0 "end"