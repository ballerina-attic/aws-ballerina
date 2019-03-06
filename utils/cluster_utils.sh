#!/bin/bash
# Copyright (c) 2019, WSO2 Inc. (http://wso2.org) All Rights Reserved.
#
# WSO2 Inc. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

. ${parent_path}/common_utils.sh
. ${parent_path}/constants.sh

# Creates an EKS cluster with following default properties. Cluster name also will be generated inside the function.
# cluster region - "us-east-1"
# retry attempts - 3
# max nodes - 3
# min nodes - 1
# node type - t2.small
# zones - us-east-1a,us-east-1b,us-east-1d
#
# $1 - The directory to write any output resources to. This directory is provided as the second param ($2) to the
#      infra script. Pass that exact directory here.
#      A custom kubeconfig file named ballerina-config.yaml is created and copied to this directory which would
#      contain the cluster details required at the deployment stage.
#      The name of this file will be written to infrastructure.properties file inside this directory, against the key
#      "ConfigFileName"
#      Also, "ClusterName", and "ClusterRegion" properties will be written to infrastructure-cleanup.properties
#      inside this directory. These would be used in the resource clean up stage.
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

    infra_cleanup_props[ClusterName]=${cluster_name}
    infra_cleanup_props[ClusterRegion]=${cluster_region}

    write_to_properties_file ${output_dir}/infrastructure-cleanup.properties infra_cleanup_props

    echo "ConfigFileName=${config_file_name}">> ${output_dir}/infrastructure.properties
}

# This creates the cluster with default properties, but does not write any information to the output directory.
# If you use this, you need to take care of passing on properties to later stages such as dpeloyment/resource cleanup
# Also this will result in the creation of a custom kubeconfig named "ballerina-config.yaml" copied to the output
# directory which needs to be passed as a parameter to this function.
#
# $1 - Output directory to write kubeconfig file into.
# $2 - Name of the cluster to be created.
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

# This creates an EKS cluster with provided parameters.
#
# $1 - No of retry attempts
# $2 - Cluster name
# $3 - Cluster region
# $4 - Max nodes
# $5 - Min nodes
# $6 - Node type
# $7 - Zones
# $8 - Kubeconfig file name with the path
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

# Generates a random name for the EKS cluster prefixed with "ballerina-cluster"
function generate_random_cluster_name() {
    echo $(generate_random_name "ballerina-cluster")
}

# Deletes the EKS cluster and related resources, provided the cluster name
#
# $1 - Name of the cluster
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

    echo " cluster resources deletion triggered"
}

# Deletes the provided kubernetes services
#
# $1 - A comma separate string of service names
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

# Deletes all k8s resources in the used namespace. The relevant namespace is taken from
# infrastructure-cleanup.properties.
function cleanup_k8s_resources() {
    local -n __infra_cleanup_config=$1
    local namespace=${__infra_cleanup_config[NamespacesToCleanup]}
    kubectl -n ${namespace} delete deployment,po,svc --all
}

function read_infra_cleanup_props() {
    # Read configuration into an associative array
    local input_dir=$1
    local -n __infra_cleanup_config=$2
    read_property_file "${input_dir}/infrastructure-cleanup.properties" __infra_cleanup_config
}