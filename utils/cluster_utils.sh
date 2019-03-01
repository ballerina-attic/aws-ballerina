#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

. ${parent_path}/common_utils.sh
. ${parent_path}/constants.sh

function create_default_cluster_and_write_infra_properties() {
    local output_dir=$1
    local cluster_name=$(generate_random_cluster_name)
    local cluster_region="us-east-1"
    local retry_attempts=3
    local max_nodes=3
    local min_nodes=1
    local node_type="t2.small"
    local zones="us-east-1a,us-east-1b,us-east-1d"
    local config_file_name=ballerina-config.yaml
    local config_file=${output_dir}/${config_file_name}

    create_cluster ${retry_attempts} ${cluster_name} ${cluster_region} ${max_nodes} ${min_nodes} ${node_type} ${zones} ${config_file}

    declare -A infra_cleanup_props;

    infra_cleanup_props[${cluster_name_key}]=${cluster_name}
    infra_cleanup_props[${cluster_region_key}]=${cluster_region}

    write_to_properties_file ${output_dir}/infrastructure-cleanup.properties infra_cleanup_props

    echo "${config_filename_key}=${config_file_name}">> ${output_dir}/infrastructure.properties
}

# $1 - output dir
function create_default_cluster() {
    local output_dir=$1
    local cluster_name=$2
    local cluster_region="us-east-1"
    local retry_attempts=3
    local max_nodes=3
    local min_nodes=1
    local node_type="t2.small"
    local zones="us-east-1a,us-east-1b,us-east-1d"
    local config_file_name=ballerina-config.yaml
    local config_file=${output_dir}/${config_file_name}

    create_cluster ${retry_attempts} ${cluster_name} ${cluster_region} ${max_nodes} ${min_nodes} ${node_type} ${zones} ${config_file}
}
# $1 - No of retry attempts
function create_cluster() {
    local retry_attempts=$1
    local cluster_name=$2
    local cluster_region=$3
    local max_nodes=$4
    local min_nodes=$5
    local node_type=$6
    local zones=$7
    local kubeconfig_file=$8
    local status=""
    while [ "${status}" != "ACTIVE" ] && [ "${retry_attempts}" -gt 0 ]
    do
        eksctl create cluster --name ${cluster_name} --region ${cluster_region} --nodes-max ${max_nodes} --nodes-min ${min_nodes} --node-type ${node_type} --zones=${zones} --kubeconfig=${kubeconfig_file}
        #Failed cluster creation - another cluster is being created, so wait for cluster to be created - This needs to be done
        #in case there are multiple test plans are created. i.e. There multiple infra combinations.
        if [ $? -ne 0 ]; then
             echo "Waiting for service role.."
             aws cloudformation wait stack-create-complete --stack-name=EKS-$cluster_name-ServiceRole
             echo "Waiting for vpc.."
             aws cloudformation wait stack-create-complete --stack-name=EKS-$cluster_name-VPC
             echo "Waiting for Control Plane.."
             aws cloudformation wait stack-create-complete --stack-name=EKS-$cluster_name-ControlPlane
             echo "Waiting for node-group.."
             aws cloudformation wait stack-create-complete --stack-name=EKS-$cluster_name-DefaultNodeGroup
        else
            #Configure the security group of nodes to allow traffic from outside
            node_security_group=$(aws ec2 describe-security-groups --filter Name=tag:aws:cloudformation:logical-id,Values=NodeSecurityGroup --query="SecurityGroups[0].GroupId" --output=text)
            aws ec2 authorize-security-group-ingress --group-id $node_security_group --protocol tcp --port 0-65535 --cidr 0.0.0.0/0
        fi
        status=$(aws eks describe-cluster --name ${cluster_name} --query="[cluster.status]" --output=text)
        echo "Status is "$status
        retry_attempts=$((${retry_attempts}-1))
        echo "attempts left : "${retry_attempts}
    done

    #if the status is not active by this phase the cluster creation has failed, hence exiting the script in error state
    if [ "${status}" != "ACTIVE" ];then
        echo "state is not active"
        exit 1
    fi
}

function generate_random_cluster_name() {
    echo $(generate_ramdom_name "ballerina-cluster")
}

# $1 - Property file
# $2 - associative array
# How to call
# declare -A somearray
# read_property_file testplan-props.properties somearray
function read_property_file() {
    local testplan_properties=$1
    # Read configuration into an associative array
    # IFS is the 'internal field separator'. In this case, your file uses '='
    local -n CONFIG=$2
    IFS="="
    while read -r key value
    do
         CONFIG[$key]=$value
    done < ${testplan_properties}
    unset IFS
}

function cleanup_cluster() {
    local cluster_name=$1
    #delete cluster resources
    aws cloudformation delete-stack --stack-name "${cluster_name}-worker-nodes"
    aws eks delete-cluster --name "${cluster_name}"
    aws eks wait cluster-deleted --name "${cluster_name}"
    aws eks describe-cluster --name "${cluster_name}" --query "cluster.status"

    aws cloudformation delete-stack --stack-name=EKS-$cluster_name-ControlPlane
    aws cloudformation wait stack-delete-complete --stack-name=EKS-$cluster_name-ControlPlane

    aws cloudformation delete-stack --stack-name=EKS-$cluster_name-ServiceRole
    aws cloudformation wait stack-delete-complete --stack-name=EKS-$cluster_name-ServiceRole

    aws cloudformation delete-stack --stack-name=EKS-$cluster_name-DefaultNodeGroup
    aws cloudformation wait stack-delete-complete --stack-name=EKS-$cluster_name-DefaultNodeGroup

    aws cloudformation delete-stack --stack-name=EKS-$cluster_name-VPC


    #eksctl delete cluster --name=$cluster_name
    echo " cluster resources deletion triggered"

}

function delete_k8s_services() {
    services_to_be_deleted=$1
    IFS=',' read -r -a services_array <<< ${services_to_be_deleted}
    unset IFS

    for service in "${services_array[@]}"
    do
       echo "Deleting $service"
       kubectl delete svc ${service}
    done
}