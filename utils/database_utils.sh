#!/bin/bash

#current_dir="$(dirname "$0")"
#
#. ${current_dir}/common_utils.sh
#. ${current_dir}/constants.sh

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

. ${parent_path}/common_utils.sh
. ${parent_path}/constants.sh

declare mysql_port=3306
declare sql_server_se_port=1433
declare oracle_se2_port=1521


# $1 - database type
# $2 - database version
# $3 - database name
function create_database() {
    local db_type=$1
    local db_version=$2
    local database_name=$3
    local __db_host=$4

    aws rds create-db-instance --db-instance-identifier ${database_name} \
        --db-instance-class db.t2.micro \
        --engine ${db_type} \
        --allocated-storage 10 \
        --master-username masterawsuser \
        --master-user-password masteruserpassword \
        --backup-retention-period 0\
        --engine-version ${db_version}

    aws rds wait  db-instance-available  --db-instance-identifier "$database_name"

    eval $__db_host=$(aws rds describe-db-instances --db-instance-identifier="$database_name" --query="[DBInstances][][Endpoint][].{Address:Address}" --output=text);
    #echo ${db_host}
}

function create_default_database_and_write_infra_properties() {
    local output_dir=$1
    declare -A db_details
    read_property_file ${output_dir}/testplan-props.properties db_details

    database_type=${db_details["DBEngine"]}
    database_version=${db_details["DBEngineVersion"]}
    database_name=$(generate_random_db_name)

    #### CREATE DATABASE AND RETRIEVE THE HOST
    create_database ${database_type} ${database_version} ${database_name} database_host

    #### WRITE INFRA PROPERTIES TO BE PROPAGATED INTO DEPLOYMENT STAGE
    declare -A infra_props;
    infra_props[${database_host_key}]=${database_host}
    infra_props[${database_port_key}]=$(get_db_port ${database_type})
    infra_props[${database_username_key}]="masterawsuser"
    infra_props[${database_password_key}]="masteruserpassword"
    infra_props[${database_name_key}]=${database_name}

    write_to_properties_file ${output_dir}/infrastructure.properties infra_props
}

function generate_random_db_name() {
    echo $(generate_ramdom_name "ballerina-kubernetes")
}

#$1 - db type
function get_db_port() {
    local db_type=$1
    if [ ${db_type} == "mysql" ];then
        echo ${mysql_port}
    elif [ ${db_type} == "sqlserver-se" ];then
        echo ${sql_server_se_port}
    elif [ ${db_type} == "oracle-se2" ];then
        echo ${oracle_se2_port}
    else
        echo -1
    fi
}