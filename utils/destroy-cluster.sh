#!bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
grand_parent_path=$(dirname ${parent_path})

. ${parent_path}/cluster_utils.sh

echo "Resource deletion script is being executed !"
echo "First argument"
echo ${1}
DIR=${2}
echo $DIR
ls ${DIR}

# Read configuration into an associative array
declare -A infra_cleanup_config
read_property_file "${DIR}/infrastructure-cleanup.properties" infra_cleanup_config

#delete kubernetes services
services_to_be_deleted=${infra_cleanup_config[ServicesToBeDeleted]}
delete_k8s_services services_to_be_deleted

#delete database
db_identifier=${infra_cleanup_config[DatabaseName]}
aws rds delete-db-instance --db-instance-identifier "$db_identifier" --skip-final-snapshot
echo "rds deletion triggered"

cluster_name=${infra_cleanup_config[ClusterName]}
cleanup_cluster ${cluster_name}
