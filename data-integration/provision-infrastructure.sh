#!bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
grand_parent_path=$(dirname ${parent_path})

. ${grand_parent_path}/utils/cluster_utils.sh
. ${grand_parent_path}/utils/database_utils.sh
. ${grand_parent_path}/utils/common_utils.sh

output_dir=$2
echo ${output_dir}

echo "CREATE DEFAULT CLUSTER"
cluster_name=$(generate_random_cluster_name)
cluster_region="us-east-1"
config_file_name=ballerina-config.yaml
config_file=${output_dir}/${config_file_name}

create_default_cluster ${output_dir} ${cluster_name}

echo "READ DATABASE DETAILS FROM testplan-props.properties"
declare -A db_details
read_property_file ${output_dir}/testplan-props.properties db_details

database_type=${db_details["DBEngine"]}
database_version=${db_details["DBEngineVersion"]}
database_name=$(generate_random_db_name)

echo "CREATE DATABASE AND RETRIEVE THE HOST"
echo "DATABASE DETAILS: DB_TYPE: ${database_type} | DB_VERSION:${database_version} | DB_NAME: ${database_name}"
create_database ${database_type} ${database_version} ${database_name} database_host
echo "DBHOST: $database_host"

echo "CREATE DB OVER"

#### WRITE INFRA PROPERTIES TO BE PROPAGATED INTO DEPLOYMENT STAGE
declare -A infra_props;
infra_props[${database_host_key}]=${database_host}
infra_props[${database_port_key}]=$(get_db_port ${database_type})
infra_props[${database_username_key}]="masterawsuser"
infra_props[${database_password_key}]="masteruserpassword"
infra_props[${config_filename_key}]=${config_file_name}
infra_props[${database_name_key}]=${database_name}

write_to_properties_file ${output_dir}/infrastructure.properties infra_props

#### WRITE INFRA CLEANUP PRPERTIES TO PROPAGATED TO THE CLEANUP STAGE
declare -A infra_cleanup_props;
infra_cleanup_props[${database_name_key}]=${database_name}
infra_cleanup_props[${cluster_name_key}]=${cluster_name}
infra_cleanup_props[${cluster_region_key}]=${cluster_region}

write_to_properties_file ${output_dir}/infrastructure-cleanup.properties infra_cleanup_props
echo "PROVISION INFRA OVER!!!!"
