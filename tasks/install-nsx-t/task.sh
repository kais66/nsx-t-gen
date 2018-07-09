#!/bin/bash

set -e

export ROOT_DIR=`pwd`

export TASKS_DIR=$(dirname $BASH_SOURCE)
export PIPELINE_DIR=$(cd $TASKS_DIR/../../ && pwd)
export FUNCTIONS_DIR=$(cd $PIPELINE_DIR/functions && pwd)

export OVA_ISO_PATH='/root/ISOs/CHGA'
export NSX_T_MANAGER_OVA=$(ls $ROOT_DIR/nsx-mgr-ova)
export NSX_T_CONTROLLER_OVA=$(ls $ROOT_DIR/nsx-ctrl-ova)
export NSX_T_EDGE_OVA=$(ls $ROOT_DIR/nsx-edge-ova)

source $FUNCTIONS_DIR/copy_ovas.sh
source $FUNCTIONS_DIR/create_ansible_cfg.sh
source $FUNCTIONS_DIR/create_answerfile.sh
source $FUNCTIONS_DIR/create_hosts.sh
source $FUNCTIONS_DIR/create_extra_yaml_args.sh
source $FUNCTIONS_DIR/check_null_variables.sh

# Default installer name to be used for tags
if [ "$NSX_T_INSTALLER" == "" ]; then
	NSX_T_INSTALLER='nsx-t-gen'
fi

function check_status_up {
	ip_set=$1
	type_of_resource=$2
	status_up=true

	resources_down_count=0
	resources_configured=$(echo $ip_set | sed -e 's/,/ /g' | awk '{print NF}' )
	for resource_ip in $(echo $ip_set | sed -e 's/,/ /g' )
	do
		# no netcat on the docker image
		#status=$(nc -vz ${resource_ip} 22 2>&1 | grep -i succeeded || true)
		# following hangs on bad ports
		#status=$( </dev/tcp/${resource_ip}/22 && echo true || echo false)
		timeout 15 bash -c "(echo > /dev/tcp/${resource_ip}/22) >/dev/null 2>&1"
		status=$?
		if [ "$status" != "0" ]; then
			status_up=false
			resources_down_count=$(expr $resources_down_count + 1)
		fi
	done

	if [ "$status_up" == "true" ]; then
		(>&2 echo "All VMs of type ${type_of_resource} up, total: ${resources_configured}")
		echo "true"
		return
	fi

  if [ "$resources_down_count" != "$resources_configured" ]; then
      (>&2 echo "Mismatch in number of VMs of type ${type_of_resource} that are expected to be up!!")
      (>&2 echo "Configured ${type_of_resource} VM total: ${resources_configured}, VM down: ${resources_down_count}")
      (>&2 echo "Delete pre-created vms of type ${type_of_resource} and start over!!")
      (>&2 echo "If the vms are up and accessible and suspect its a timing issue, restart the job again!!")
      (>&2 echo "Exiting now !!")
      exit -1
  else
      (>&2 echo "All VMs of type ${type_of_resource} down, total: ${resources_configured}")
      (>&2 echo "  Would need to deploy ${type_of_resource} ovas")
	fi

	echo "false"
	return
}

DEBUG=""
if [ "$ENABLE_ANSIBLE_DEBUG" == "true" ]; then
  DEBUG="-vvv"
fi

create_hosts
# create_answerfile # TODO: not sure if answerfile.yml is used anywhere
# create_ansible_cfg
# create_extra_yaml_args # TODO: check if the resource spec (e.g. ip pool) changed in nsxt-ansible
create_customize_ova_params

cp hosts answerfile.yml ansible.cfg extra_yaml_args.yml customize_ova_vars.yml nsxt-ansible/.
cd nsxt-ansible

echo ""

# Check if the status and count of Mgr, Ctrl, Edge
nsx_mgr_up_status=$(check_status_up $NSX_T_MANAGER_IP "NSX Mgr")
nsx_controller_up_status=$(check_status_up $NSX_T_CONTROLLER_IPS "NSX Controller")
nsx_edge_up_status=$(check_status_up $NSX_T_EDGE_IPS "NSX Edge")
echo ""

STATUS=0
# Copy over the ovas if any of the resources are not up
if [ "$nsx_mgr_up_status" != "true" -o  "$nsx_controller_up_status" != "true" -o "$nsx_edge_up_status" != "true" ]; then
	echo "Detected one of the vms (mgr, controller, edge) are not yet up, preparing the ovas"
	echo ""

	# # install_ovftool
	# copy_ovas_to_OVA_ISO_PATH
	# create_customize_ova_params

	# TODO: whether it's needed to customize
	if [ "$NSX_T_KEEP_RESERVATION" != "true" ]; then
		echo "Reservation turned off, customizing the ovas to turn off reservation!!"
		echo ""
		# ansible-playbook $DEBUG -i localhost customize_ovas.yml -e @customize_ova_vars.yml
		echo ""
	fi
fi

# TODO: change the following to run the overall workflow for install and creation of resources
# Deploy the Mgr ova if its not up
if [ "$nsx_mgr_up_status" != "true" ]; then
	# ansible-playbook $DEBUG -i hosts deploy_mgr.yml -e @extra_yaml_args.yml
	ansible-playbook $DEBUG -i hosts basic_topology.yml
	STATUS=$?

	if [[ $STATUS != 0 ]]; then
		echo "Deployment of NSX Mgr OVA failed, vms failed to come up!!"
		echo "Check error logs"
		echo ""
		exit $STATUS
	else
		echo "Deployment of NSX Mgr ova succcessfull!! Continuing with rest of configuration!!"
		echo ""
	fi
else
	echo "NSX Mgr up already, skipping deploying of the Mgr ova!!"
fi


# Give some time for vm services to be up before checking the status of the vm instances
echo "Wait for 30 seconds before checking if all NSX VMs are up"
sleep 30
echo ""

echo "Rechecking the status and count of Mgr, Ctrl, Edge instances !!"
nsx_mgr_up_status=$(check_status_up $NSX_T_MANAGER_IP "NSX Mgr")
nsx_controller_up_status=$(check_status_up $NSX_T_CONTROLLER_IPS "NSX Controller")
nsx_edge_up_status=$(check_status_up $NSX_T_EDGE_IPS "NSX Edge")
echo ""

if [ "$nsx_mgr_up_status" != "true" \
			-o "$nsx_controller_up_status" != "true" \
			-o "$nsx_edge_up_status" != "true" ]; then
# if [ "$nsx_mgr_up_status" != "true" \
# 			-o "$nsx_controller_up_status" != "true" ]; then
	echo "Some problem with the VMs, one or more of the vms (mgr, controller, edge) failed to come up or not accessible!"
	echo "Check the related vms!!"
	echo "Notes: "
	echo "   Its possible a vm is not reachable or temporarily unavailable, try restarting the concourse job"
	echo "   In rare cases, delete any older non-running vms (same name can affect new ova deployment) "
	echo "       as well as any vms that did not form a not complete set (like only 1 controller up out of 3)"
	echo "   Check also the FAQs here: https://github.com/sparameswaran/nsx-t-gen/blob/master/docs/faqs.md"
	exit 1
fi
echo ""

# Configure the controllers
# NO_OF_EDGES_CONFIGURED=$(echo $NSX_T_EDGE_IPS | sed -e 's/,/ /g' | awk '{print NF}' )
# NO_OF_CONTROLLERS_CONFIGURED=$(echo $NSX_T_CONTROLLER_IPS | sed -e 's/,/ /g' | awk '{print NF}' )

# # Total number of controllers should be mgr + no of controllers
# EXPECTED_TOTAL_CONTROLLERS=$(expr 1 + $NO_OF_CONTROLLERS_CONFIGURED )

# CURRENT_TOTAL_EDGES=$(curl -k -u "admin:$NSX_T_MANAGER_ADMIN_PWD" \
#                     https://${NSX_T_MANAGER_IP}/api/v1/fabric/nodes \
#                      2>/dev/null | jq '.result_count' )

# CURRENT_TOTAL_CONTROLLERS=$(curl -k -u "admin:$NSX_T_MANAGER_ADMIN_PWD" \
#                     https://${NSX_T_MANAGER_IP}/api/v1/cluster/nodes \
#                      2>/dev/null | jq '.result_count' )



echo "Successfully finished with Install!!"

exit 0
