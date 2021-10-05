#!/bin/bash

set -e
trap 'kill $(jobs -p)' SIGINT SIGTERM EXIT


# Populate the install-config.yaml with secret information
if [[  -z "${SSH_PUB_KEY_PATH}" ]]
then
        echo "Please provide the path to your ssh public key in the ENV SSH_PUB_KEY_PATH"
fi
if [[  -z "${PULL_SECRET_PATH}" ]]
then
        echo "Please provide the path to your pull secret in the ENV PULL_SECRET_PATH"
fi
SSH_PUB_KEY=$(cat "${SSH_PUB_KEY_PATH}")
PULL_SECRET=$(cat "${PULL_SECRET_PATH}")
echo "pullSecret: '${PULL_SECRET}'" >> install-config.yaml
echo "sshKey: |
  ${SSH_PUB_KEY}" >> install-config.yaml


ocp_latest_stable_release=$(curl -s -L -k https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/release.txt | grep "Pull From:" | cut -d":" -f2- | tr -d " ")
ocp_latest_release=$(curl -s -L -k https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/release.txt  | grep "Pull From:" | cut -d":" -f2- | tr -d " ")
ocp_latest_candidate=$(curl -s -L -k https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/candidate/release.txt | grep "Pull From:" | cut -d":" -f2- | tr -d " ")
ocp_latest_nightly=$(curl -s -L -k https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp-dev-preview/latest/release.txt | grep "Pull From:" | cut -d":" -f2- | tr -d " ")

export CLUSTER_NAME="${CLUSTER_NAME:-ocpp}"
export INSTALL_DIR=${CLUSTER_NAME}
export NW_SUBNET="${NW_SUBNET:-192.168.126}"
export NW_RESOLVER="${NW_SUBNET}.1"
export NW_CIDR="${NW_SUBNET}.0/24"
export NW_IFACE="${NW_IFACE:-tt0}"
export DOMAIN="${DOMAIN:-rtalur.com}"
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-$ocp_latest_stable_release}"
export LIBVIRT_MASTER_MEMORY="${LIBVIRT_MASTER_MEMORY:-24576}"
export LIBVIRT_MASTER_CPU="${LIBVIRT_MASTER_CPU:-8}"
export LIBVIRT_MASTER_DISK_SIZE="${LIBVIRT_MASTER_DISK_SIZE:-$((40*1073741824))}"
export LIBVIRT_WORKER_MEMORY="${LIBVIRT_WORKER_MEMORY:-24576}"
export LIBVIRT_WORKER_CPU="${LIBVIRT_WORKER_CPU:-8}"
export LIBVIRT_WORKER_DISK_SIZE="${LIBVIRT_WORKER_DISK_SIZE:-$((40*1073741824))}"
export MASTER_NODE_COUNT="${MASTER_NODE_COUNT:-1}"
export WORKER_NODE_COUNT="${WORKER_NODE_COUNT:-3}"
export GLOBAL_INSTALL_TIMEOUT="${GLOBAL_INSTALL_TIMEOUT:-7200}"

if [[ $1 == "abcd" ]]
then
        ./disk-detach.sh
fi

if [[ $1 == "all" || $1 == "cluster" ]]
then
        mkdir -p ${INSTALL_DIR}/logs
        cp install-config.yaml ${INSTALL_DIR}/
        yq write --inplace ${INSTALL_DIR}/install-config.yaml controlPlane[replicas] ${MASTER_NODE_COUNT}
        yq write --inplace ${INSTALL_DIR}/install-config.yaml compute[0].replicas ${WORKER_NODE_COUNT}
        sed -i -e "s/DOMAIN/${DOMAIN}/g" ${INSTALL_DIR}/install-config.yaml
        sed -i -e "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ${INSTALL_DIR}/install-config.yaml
        sed -i -e "s#NW_CIDR#${NW_CIDR}#g" ${INSTALL_DIR}/install-config.yaml
        sed -i -e "s/NW_IFACE/${NW_IFACE}/g" ${INSTALL_DIR}/install-config.yaml
        sed -i -e "s/NW_SUBNET/${NW_SUBNET}/g" ${INSTALL_DIR}/install-config.yaml
        echo "Will run installer" | tee -a ${INSTALL_DIR}/logs/install.log
        ./openshift-install --dir=${INSTALL_DIR} create manifests

        # Edit master settings
        sed -i -e "s/8192/${LIBVIRT_MASTER_MEMORY}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_master-machines-0.yaml
        sed -i -e "s/.*domainVcpu.*/      domainVcpu: ${LIBVIRT_MASTER_CPU}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_master-machines-0.yaml
        sed -i -e "s/volume:/volume:\n        volumeSize: ${LIBVIRT_MASTER_DISK_SIZE}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_master-machines-0.yaml
        if [[ ${WORKER_NODE_COUNT} -eq 0 ]]
        then
                sed -i 's/mastersSchedulable: false/mastersSchedulable: true/' ${INSTALL_DIR}/manifests/cluster-scheduler-02-config.yml
        fi

        # Edit worker settings
        if [[ ${WORKER_NODE_COUNT} -gt 0 ]]
        then
                sed -i -e "s/8192/${LIBVIRT_WORKER_MEMORY}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_worker-machineset-0.yaml
                sed -i -e "s/.*domainVcpu.*/          domainVcpu: ${LIBVIRT_WORKER_CPU}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_worker-machineset-0.yaml
                sed -i -e "s/volume:/volume:\n            volumeSize: ${LIBVIRT_WORKER_DISK_SIZE}/g" ${INSTALL_DIR}/openshift/99_openshift-cluster-api_worker-machineset-0.yaml
        fi
        ./netset.sh &
        ./disk-attach.sh &
	./patch.sh &
        ./openshift-install --dir=${INSTALL_DIR} create cluster --log-level debug 2>&1
        wait
fi

if [[ $1 == "wfic" ]]
then
        ./openshift-install --dir=${INSTALL_DIR} wait-for install-complete
fi

if [[ $1 == "netset" ]]
then
        ./netset.sh
fi

if [[ $1 == "diskattach" ]]
then
        ./disk-attach.sh
fi

if [[ $1 == "destroy" ]]
then
        set +e
        ./disk-detach.sh
        ./openshift-install --log-level=debug --dir=${CLUSTER_NAME} destroy cluster
        net_name=$(virsh net-list --name | grep ${CLUSTER_NAME})
        virsh net-destroy $net_name
        virsh net-undefine $net_name
        if [[ ! -z "${INSTALL_DIR}" ]]
        then
                rm -rf ./${INSTALL_DIR}
        fi
fi
