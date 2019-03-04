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
    local zone_1="us-east-1a"
    local zone_2="us-east-1b"
    local config_file_name=ballerina-config.yaml
    local config_file=${output_dir}/${config_file_name}

    create_cluster_and_write_to_infra_properties ${output_dir} ${retry_attempts} ${cluster_name} ${cluster_region} ${max_nodes} ${min_nodes} ${node_type} ${zone_1} ${zone_2} ${config_file}
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
function create_cluster_and_write_to_infra_properties() {
    local output_dir=$1
    local retry_attempts=$2
    local cluster_name=$3
    local cluster_region=$4
    local max_nodes=$5
    local min_nodes=$6
    local node_type=$7
    local zone_1=$8
    local zone_2=$9
    local kubeconfig_file=$10
    local status=""
    while [ "${status}" != "ACTIVE" ] && [ "${retry_attempts}" -gt 0 ]
    do
       vpc_cidr_block="10.0.0.0/28"
       vpc_id=$(aws ec2 create-vpc --cidr-block ${vpc_cidr_block} --query 'Vpc.VpcId')

       aws ec2 wait vpc-available --vpc-ids ${vpc_id}

       echo "Without quotes"
       aws ec2 describe-vpcs --vpc-ids ${vpc_id}
       echo "With quotes"
       aws ec2 describe-vpcs --vpc-ids "$vpc_id"

       subnet_cidr_block_1="10.0.0.0/29"
       subnet_cidr_block_2="10.0.0.8/29"

       subnet_1=$(aws ec2 create-subnet --availability-zone ${zone_1} --cidr-block ${subnet_cidr_block_1} --vpc-id ${vpc_id} --query 'Subnet.SubnetId')
       subnet_2=$(aws ec2 create-subnet --availability-zone ${zone_2} --cidr-block ${subnet_cidr_block_2} --vpc-id ${vpc_id} --query 'Subnet.SubnetId')

       aws ec2 describe-subnets --subnet-ids ${subnet_1}
       aws ec2 describe-subnets --subnet-ids ${subnet_2}

       sg_1=${cluster_name}-sg1
       sg_2=${cluster_name}-sg2

       aws ec2 create-security-group --description "${sg_1} security group" --group-name ${sg_1} --vpc-id ${vpc_id}
       aws ec2 create-security-group --description "${sg_2} security group" --group-name ${sg_2} --vpc-id ${vpc_id}

       aws ec2 describe-security-groups --group-names ${sg_1}
       aws ec2 describe-security-groups --group-names ${sg_2}

       aws eks create-cluster --name ${cluster_name} --role-arn ${iam_role} --resources-vpc-config subnetIds=${subnet_1},${subnet_2},securityGroupIds=${sg_1},${sg_2}

        #Failed cluster creation - another cluster is being created, so wait for cluster to be created - This needs to be done
        #in case there are multiple test plans are created. i.e. There multiple infra combinations.
        if [ $? -ne 0 ]; then
            echo "Waiting for cluster creation"
            aws eks wait --name ${cluster_name}
        else
            #Configure the security group of nodes to allow traffic from outside
            aws ec2 authorize-security-group-ingress --group-id ${sg_1} --protocol tcp --port 0-65535 --cidr 0.0.0.0/0
            aws ec2 authorize-security-group-ingress --group-id ${sg_2} --protocol tcp --port 0-65535 --cidr 0.0.0.0/0

        fi
        status=$(aws eks describe-cluster --name ${cluster_name} --query="[cluster.status]" --output=text)
        echo "Status is "${status}
        retry_attempts=$((${retry_attempts}-1))
        echo "attempts left : "${retry_attempts}
    done

    declare -A infra_cleanup_props;

    infra_cleanup_props[${cluster_name_key}]=${cluster_name}
    infra_cleanup_props[${cluster_region_key}]=${cluster_region}
    infra_cleanup_props[${subnet1_key}]=${subnet_1}
    infra_cleanup_props[${subnet2_key}]=${subnet_2}
    infra_cleanup_props[${security_group1_key}]=${sg_1}
    infra_cleanup_props[${security_group2_key}]=${sg_2}
    infra_cleanup_props[${vpc_key}]=${vpc_id}

    write_to_properties_file ${output_dir}/infrastructure-cleanup.properties infra_cleanup_props

    echo "${config_filename_key}=${kubeconfig_file}">> ${output_dir}/infrastructure.properties

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

function generate_random_vpc_name() {
    echo $(generate_random_name "ballerina-vpc")
}

function generate_random_security_group_name() {
    echo $(generate_random_name "ballerina-sg")
}

# Reads a property file in to the passed associative array. Note that the associative array should be declared before
# calling this function.
#
# $1 - Property file path
# $2 - associative array
#
# Usage example:
# declare -A some_array
# read_property_file /path/to/some-file.properties some_array
function read_property_file() {
    local property_file_path=$1
    # Read configuration into an associative array
    # IFS is the 'internal field separator'. In this case, your file uses '='
    local -n props=$2
    IFS="="
    while read -r key value
    do
         props[$key]=$value
    done < ${property_file_path}
    unset IFS
}

# Deletes the EKS cluster and related resources, provided the cluster name
#
# $1 - Name of the cluster
function cleanup_cluster() {
    local output_dir=$1

    declare -A infra_cleanup_props
    read_property_file ${output_dir}/infrastructure-cleanup.properties infra_cleanup_props
    cluster_name=infra_cleanup_props[${cluster_name_key}]
    security_group1=infra_cleanup_props[${security_group1_key}]
    security_group2=infra_cleanup_props[${security_group2_key}]
    subnet1=infra_cleanup_props[${subnet1_key}]
    subnet2=infra_cleanup_props[${subnet2_key}]
    vpc=infra_cleanup_props[${VPC}]

    aws eks delete-cluster --name ${cluster_name}
    aws eks wait cluster-deleted --name ${cluster_name}

    aws ec2 delete-security-group --group-id ${security_group1}
    aws ec2 delete-security-group --group-id ${security_group2}

    aws ec2 delete-subnet --subnet-id ${subnet1}
    aws ec2 delete-subnet --subnet-id ${subnet2}

    aws ec2 delete-vpc --vpc-id ${vpc}

    echo "Cluster and resources deleted"
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
