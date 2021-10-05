#!/bin/bash

count=0
echo $0 "Will wait for worker nodes to be created and attach additional disks"
while [[ $(virsh list --all --name | grep  "${CLUSTER_NAME}-.*-worker" | wc -l) != "${WORKER_NODE_COUNT}" ]]  ; do
        if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                echo
                echo "timed out waiting for the worker nodes to be created"
                exit 1
        fi
        count=$((count + 1))
        sleep 1
done

declare -a  WORKERS
for worker in $(virsh list --all --name | grep ${CLUSTER_NAME} | grep worker) ; do
        WORKERS+=("${worker}")
done

for worker in ${WORKERS[@]} ; do
        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-1.qcow2 100G
        virsh -c qemu:///system attach-disk "${worker}" --source  /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-1.qcow2 --target vdb --cache none --driver qemu --subdriver qcow2 --live --persistent
        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-2.qcow2 100G
        virsh -c qemu:///system attach-disk "${worker}" --source  /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-2.qcow2 --target vdc --cache none --driver qemu --subdriver qcow2 --live --persistent
        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-3.qcow2 100G
        virsh -c qemu:///system attach-disk "${worker}" --source  /var/lib/libvirt/images/${worker}-${CLUSTER_NAME}-${DOMAIN}-100G-3.qcow2 --target vdd --cache none --driver qemu --subdriver qcow2 --live --persistent
done

echo $0 "end"
