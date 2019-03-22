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

# Writes the properties in to the provided file path, given an associative array containing the key, value pairs.
#
# $1 File path
function write_to_properties_file() {
    local properties_file_path=$1
    local -n properties_array=$2

    # Keys are accessed through exclamation point
    for i in ${!properties_array[@]}
    do
      echo ${i}=${properties_array[$i]} >> ${properties_file_path}
    done
}

# Generates a random string with the provided prefix
#
# $1 - prefix
function generate_random_name() {
    local prefix=$1
    local new_uuid=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo ${prefix}-${new_uuid}
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
    local -n __props=$2
    IFS="="
    while read -r key value
    do
         __props[$key]=$value
    done < ${property_file_path}
    unset IFS
}
