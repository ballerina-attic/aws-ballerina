#!bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
grand_parent_path=$(dirname ${parent_path})

. ${grand_parent_path}/utils/cluster_utils.sh
. ${grand_parent_path}/utils/database_utils.sh

output_dir=$2
echo ${output_dir}

create_default_cluster_and_write_infra_properties ${output_dir}

create_default_database_and_write_infra_properties ${output_dir}



