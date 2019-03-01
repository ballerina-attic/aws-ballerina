#!/bin/bash

# $1 file path
function write_to_properties_file() {
    local properties_file_path=$1
    local -n properties_array=$2

    # Keys are accessed through exclamation point
    for i in ${!properties_array[@]}
    do
      echo ${i}=${properties_array[$i]} >> ${properties_file_path}
    done
}

# $1 - prefix
function generate_ramdom_name() {
    local prefix=$1
    local new_uuid=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo ${prefix}-${new_uuid}
}