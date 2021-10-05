#!/bin/bash

count=0
echo $0 "Will wait for the kubeconfig to be created"
while ! [[ -f ${INSTALL_DIR}/auth/kubeconfig  ]]  ; do
        if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                echo
                echo $0 "timed out waiting for the kubconfig to be created"
                exit 1
        fi
        count=$((count + 1))
        sleep 1
done

if [[ ${MASTER_NODE_COUNT} -eq 1 ]]
then
        count=0
        while [[ $(oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get etcd cluster -o name 2>/dev/null) != "etcd.operator.openshift.io/cluster" ]]  ; do
                if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                        echo
                        echo $0 "timed out waiting for the etcd cluster to be created"
                        exit 1
                fi
                count=$((count + 1))
                sleep 1
        done
        oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig patch etcd cluster -p='{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}' --type=merge
fi

count=0
# As we don't have a load balancer, we will just keep the number of ingress pods same as the worker nodes
echo $0 "Will wait for the ingresscontroller to be created and patch it"
while [[ $(oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig -n openshift-ingress-operator get ingresscontroller/default -o name 2>/dev/null) != "ingresscontroller.operator.openshift.io/default" ]]  ; do
        if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                echo
                echo $0 "timed out waiting for the ingresscontroller to be created"
                exit 1
        fi
        count=$((count + 1))
        sleep 1
done
if [[ ${WORKER_NODE_COUNT} -gt 0 ]]
then
        oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig patch -n openshift-ingress-operator ingresscontroller/default --patch '{"spec":{"replicas": 3}}' --type=merge
fi
if [[ ${WORKER_NODE_COUNT} -eq 0 ]]
then
        oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig patch -n openshift-ingress-operator ingresscontroller/default --patch '{"spec":{"replicas": 1}}' --type=merge
fi


echo $0 "end"
