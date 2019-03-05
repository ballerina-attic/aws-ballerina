#!bin/bash
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
grand_parent_path=$(dirname ${parent_path})

. ${grand_parent_path}/utils/cluster_utils.sh

echo "Resource deletion script is being executed !"
input_dir=${2}

# Read configuration into an associative array
declare -A infra_cleanup_config
read_property_file "${input_dir}/infrastructure-cleanup.properties" infra_cleanup_config

#delete kubernetes services
services_to_be_deleted=${infra_cleanup_config[ServicesToBeDeleted]}
delete_k8s_services services_to_be_deleted

#delete database
db_identifier=${infra_cleanup_config[DatabaseName]}
delete_database db_identifier

#cleanup cluster
#cluster_name=${infra_cleanup_config[ClusterName]}
#cleanup_cluster ${cluster_name}
