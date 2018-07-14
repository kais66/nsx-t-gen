#!/bin/bash

function create_controller_hosts {
  count=1
  echo "[controllers]" > ctrl_vms
  for controller_ip in $(echo $controller_ips_int | sed -e 's/,/ /g')
  do
    cat >> ctrl_vms <<-EOF
  controller-${count} ip=$controller_ip hostname=${controller_hostname_prefix_int}-${count} default_gateway=${controller_default_gateway_int} prefix_length=$controller_ip_prefix_length_int
EOF
    (( count++ ))
  done
  cat >> ctrl_vms <<-EOF
[controllers:vars]
controller_cli_password="$controller_cli_password_int"
controller_root_password="$controller_root_password_int"
controller_deployment_size="$controller_deployment_size_int"
controller_compute_id="$controller_compute_id_int"
controller_storage_id="$controller_storage_id_int"
controller_management_network_id="$controller_management_network_id_int"
controller_shared_secret="$controller_shared_secret_int"
EOF

}

# TODO: update this with params from https://github.com/yasensim/nsxt-ansible/blob/master/answerfile.yml
function create_edge_hosts {
  count=1
  echo "[edge_nodes]" > edge_vms
  for edge_ip in $(echo $edge_ips_int | sed -e 's/,/ /g')
  do
    cat >> edge_vms <<-EOF
edge-${count} ip=$edge_ip hostname=${edge_hostname_prefix_int}-${count} default_gateway=$edge_default_gateway_int prefix_length=$edge_ip_prefix_length_int edge_fabric_node_name=${edge_fabric_name_prefix_int}-${count}  transport_node_name=${edge_transport_node_prefix_int}-${count}

EOF
    (( count++ ))
  done

  cat >> edge_vms <<-EOF
[edge_nodes:vars]
edge_cli_password="$edge_cli_password_int"
edge_root_password="$edge_root_password_int"
edge_deployment_size="$edge_deployment_size_int"
edge_compute_id="$edge_compute_id_int"
edge_storage_id="$edge_storage_id_int"
edge_data_network_id="$edge_data_network_id_int"
edge_management_network_id="$edge_management_network_id_int"
EOF
}

### TODO: where are transport node config params
function create_esxi_hosts {
  echo "$ESXI_HOSTS_CONFIG" > /tmp/esxi_hosts_config.yml
  touch esxi_hosts

  is_valid_yml=$(cat /tmp/esxi_hosts_config.yml  | shyaml get-values esxi_hosts || true)

  # Check if the esxi_hosts config is not empty and is valid
  if [ "$ESXI_HOSTS_CONFIG" != "" -a "$is_valid_yml" != "" ]; then

    echo "[nsxtransportnodes]" > esxi_hosts

    length=$(expr $(cat /tmp/esxi_hosts_config.yml  | shyaml get-values esxi_hosts | grep name: | wc -l) - 1 || true )
    for index in $(seq 0 $length)
    do
      ESXI_INSTANCE_HOST=$(cat /tmp/esxi_hosts_config.yml  | shyaml get-value esxi_hosts.${index}.name)
      ESXI_INSTANCE_IP=$(cat /tmp/esxi_hosts_config.yml  | shyaml get-value esxi_hosts.${index}.ip)
      ESXI_INSTANCE_PWD=$(cat /tmp/esxi_hosts_config.yml  | shyaml get-value esxi_hosts.${index}.root_pwd)
      if [ "$ESXI_INSTANCE_PWD" == "" ]; then
        ESXI_INSTANCE_PWD=$ESXI_HOSTS_ROOT_PWD
      fi

      cat >> esxi_hosts <<-EOF
$ESXI_INSTANCE_HOST  ansible_ssh_host=$ESXI_INSTANCE_IP   ansible_ssh_user=root ansible_ssh_pass=$ESXI_INSTANCE_PWD
EOF
    done
  else
    echo "esxi_hosts_config not set to valid yaml, so ignoring it"
    echo "Would use computer manager configs to add hosts!!"
    echo "" >> esxi_hosts
  fi
}

## TODO: convert = notation to : notation when specifiying variables
function create_hosts {

# TODO: set nsx manager fqdn
export NSX_T_MANAGER_SHORT_HOSTNAME=$(echo $NSX_T_MANAGER_FQDN | awk -F '\.' '{print $1}')

cat > hosts <<-EOF
[localhost]
localhost       ansible_connection=local

[localhost:vars]
sshEnabled='True'
allowSSHRootAccess='True'

vcenter_ip="$vcenter_ip_int"
vcenter_username="$vcenter_username_int"
vcenter_password="$vcenter_password_int"
vcenter_folder="$vcenter_folder_int"
vcenter_datacenter="$vcenter_datacenter_int"
vcenter_cluster="$vcenter_cluster_int"
vcenter_datastore="$vcenter_datastore_int"

mgmt_portgroup="$mgmt_portgroup_int"
dns_server="$dns_server_int"
dns_domain="$dns_domain_int"
ntp_servers="$ntp_servers_int"
default_gateway="$default_gateway_int"
netmask="$netmask_int"
nsx_image_webserver="nsx_image_webserver_int"
ova_file_name="$ova_file_name_int"

nsx_manager_ip="$nsx_manager_ip_int"
nsx_manager_username="$nsx_manager_username_int"
nsx_manager_password="$nsx_manager_password_int"
nsx_manager_assigned_hostname="$nsx_manager_assigned_hostname_int"
nsx_manager_root_pwd="$nsx_manager_root_pwd_int"
nsx_manager_deployment_size="$nsx_manager_deployment_size_int"

compute_manager_username="$compute_manager_username_int"
compute_manager_password="$compute_manager_password_int"
edge_uplink_profile_vlan="$edge_uplink_profile_vlan_int"
esxi_uplink_profile_vlan="$esxi_uplink_profile_vlan_int"
vtep_ip_pool_name="$vtep_ip_pool_name_int"
vtep_ip_pool_cidr="$vtep_ip_pool_cidr_int"
vtep_ip_pool_gateway="$vtep_ip_pool_gateway_int"
vtep_ip_pool_start="$vtep_ip_pool_start_int"
vtep_ip_pool_end="$vtep_ip_pool_end_int"

EOF

  if [ "$VCENTER_RP" == "null" ]; then
    export VCENTER_RP=""
  fi

  create_edge_hosts
  create_controller_hosts

  cat ctrl_vms >> hosts
  echo "" >> hosts
  cat edge_vms >> hosts
  echo "" >> hosts

  if  [ ! -z "$ESXI_HOSTS_CONFIG" ]; then
    create_esxi_hosts
    cat esxi_hosts >> hosts
    echo "" >> hosts
  fi

}
