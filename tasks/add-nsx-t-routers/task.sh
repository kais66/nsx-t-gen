#!/bin/bash

set -e

export ROOT_DIR=`pwd`

export TASKS_DIR=$(dirname $BASH_SOURCE)
export PIPELINE_DIR=$(cd $TASKS_DIR/../../ && pwd)
export FUNCTIONS_DIR=$(cd $PIPELINE_DIR/functions && pwd)

source $FUNCTIONS_DIR/create_hosts.sh

DEBUG=""
if [ "$ENABLE_ANSIBLE_DEBUG" == "true" ]; then
  DEBUG="-vvv"
fi

# Check if NSX MGR is up or not
nsx_mgr_up_status=$(curl -s -o /dev/null -I -w "%{http_code}" -k  https://${nsx_manager_ip_int}:443/login.jsp || true)

# Deploy the ovas if its not up
if [ $nsx_mgr_up_status -ne 200 ]; then
  echo "NSX Mgr not up yet, please deploy the ovas before configuring routers!!"
  exit -1
fi

create_hosts

# cp hosts answerfile.yml ansible.cfg extra_yaml_args.yml nsxt-ansible/.
cp hosts ${PIPELINE_DIR}/tasks/add-nsx-t-routers/basic_resources.yml ${PIPELINE_DIR}/tasks/add-nsx-t-routers/vars.yml nsxt-ansible/
cd nsxt-ansible

NO_OF_CONTROLLERS=$(curl -k -u "admin:$nsx_manager_password_int" \
                    https://${nsx_manager_ip_int}/api/v1/cluster/nodes \
                    | jq '.results[].controller_role.type' | wc -l )
if [ "$NO_OF_CONTROLLERS" -lt 2 ]; then
  echo "NSX Mgr and controller not configured yet, please cleanup incomplete vms and rerun base install before configuring routers!!"
  exit -1
fi

ansible-playbook $DEBUG -i hosts ${PIPELINE_DIR}/tasks/add-nsx-t-routers/basic_resources.yml
STATUS=$?

# for debug
sleep 6000

echo ""

exit $STATUS