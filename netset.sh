#!/bin/bash
count=0

echo $0 "Will wait for libvirt network creation and update it with dns information"
while ! virsh net-list --name | grep -q "${CLUSTER_NAME}"; do
        if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                echo
                echo $0 "timed out waiting for the libvirt network to be created"
                exit 1
        fi
        count=$((count + 1))
        sleep 1
done

# Let the host dns know that cluster.domain queries are handled by the libvirt interface dns server
sudo resolvectl dns $NW_IFACE $NW_RESOLVER
sudo resolvectl domain $NW_IFACE ~${CLUSTER_NAME}.${DOMAIN} ~api.${CLUSTER_NAME}.${DOMAIN} ~api-int.${CLUSTER_NAME}.${DOMAIN} ~oauth-openshift.apps.${CLUSTER_NAME}.${DOMAIN} ~console-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN} ~canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${DOMAIN}


if [[ ${WORKER_NODE_COUNT} -eq 0 ]]
then
        net_name=$(virsh net-list --name | grep ${CLUSTER_NAME})
        while [[ $(virsh list --all --name | grep "${CLUSTER_NAME}-.*-master" | head -n1) == "" ]] ; do
                if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                        echo
                        echo $0 "timed out waiting for the master node to be created"
                        exit 1
                fi
                count=$((count + 1))
                sleep 1
        done
        while [[ $(virsh list --all --name | grep "${CLUSTER_NAME}-.*-bootstrap" | head -n1) != "" ]] ; do
                if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                        echo
                        echo $0 "timed out waiting for the bootstrap pod to be deleted"
                        exit 1
                fi
                count=$((count + 1))
                sleep 1
        done
        master=$(virsh list --all --name | grep "${CLUSTER_NAME}-.*-master" | head -n1)
        ip=$(virsh domifaddr --domain "$master" | grep -v -e '^$' | grep -v Address |  grep -v "\-\-\-\-" | awk '{print $4}' | cut -d"/" -f1)
        while [[ -z ${ip} ]]; do
                ip=$(virsh domifaddr --domain "$master" | grep -v -e '^$' | grep -v Address |  grep -v "\-\-\-\-" | awk '{print $4}' | cut -d"/" -f1)
        done
        sudo sed -i "s/${ip}.*$/${ip} api.${CLUSTER_NAME}.${DOMAIN} api-int.${CLUSTER_NAME}.${DOMAIN} downloads-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN} grafana-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} alertmanager-main-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} prometheus-k8s-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} oauth-openshift.apps.${CLUSTER_NAME}.${DOMAIN} console-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN} canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${DOMAIN}/g" /var/lib/libvirt/dnsmasq/${net_name}.addnhosts
        dnsmasqPID=$(ps aux | grep dnsmasq | grep $net_name | grep -v grep | grep -v root | head -n1 | awk '{print $2}')
        sudo kill -HUP $dnsmasqPID
        echo $0 "edited the addnhosts files for a single master no worker configuration"
        exit 0
fi

# Once the workers are up, add their ips to the dns for all non control plane domains
net_name=$(virsh net-list --name | grep ${CLUSTER_NAME})
echo $0 "Will wait for worker nodes to be created and update dns info"
while [[ $(virsh list --all --name | grep "${CLUSTER_NAME}-.*-worker" | wc -l) != "${WORKER_NODE_COUNT}" ]] ; do
        if test ${count} -ge ${GLOBAL_INSTALL_TIMEOUT}; then
                echo
                echo $0 "timed out waiting for the worker nodes to be created"
                exit 1
        fi
        count=$((count + 1))
        sleep 1
done
declare -a  WORKERIPS
for worker in $(virsh list --all --name | grep ${CLUSTER_NAME} | grep worker) ; do
        ip=$(virsh domifaddr --domain "$worker" | grep -v -e '^$' | grep -v Address |  grep -v "\-\-\-\-" | awk '{print $4}' | cut -d"/" -f1)
        while [[ -z ${ip} ]]; do
                ip=$(virsh domifaddr --domain "$worker" | grep -v -e '^$' | grep -v Address |  grep -v "\-\-\-\-" | awk '{print $4}' | cut -d"/" -f1)
        done
        WORKERIPS+=(${ip})
done
echo number of worker IPs found: "${#WORKERIPS[@]}"
echo IPs are "${WORKERIPS[@]}"

for workerip in ${WORKERIPS[@]} ; do
        sudo echo "${workerip} downloads-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN} grafana-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} alertmanager-main-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} prometheus-k8s-openshift-monitoring.apps.${CLUSTER_NAME}.${DOMAIN} oauth-openshift.apps.${CLUSTER_NAME}.${DOMAIN} console-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN} canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${DOMAIN}" | sudo tee -a /var/lib/libvirt/dnsmasq/${net_name}.addnhosts
        dnsmasqPID=$(ps aux | grep dnsmasq | grep $net_name | grep -v grep | grep -v root | head -n1 | awk '{print $2}')
        sudo kill -HUP $dnsmasqPID

	# Ideally, we would want to use the virsh command for this. However, there is a bug that prevents us from updating the dns section like this.
	# Will probably be fixed in libvirt 7.6 or 7.8. See https://github.com/libvirt/libvirt/commit/16cb11a66adb5ebd1707c31c8f74acf79cd8bd6e
	#virsh net-update $net_name add-first dns-host "<host ip='${NW_SUBNET}.51'><hostname>oauth-openshift.apps.${CLUSTER_NAME}.${DOMAIN}</hostname><hostname>console-openshift-console.apps.${CLUSTER_NAME}.${DOMAIN}</hostname><hostname>canary-openshift-ingress-canary.apps.${CLUSTER_NAME}.${DOMAIN}</hostname></host>"
done

echo $0 "end"
