#!/bin/bash

sleep_for=${1:-300}

while true; do
    /usr/bin/araddclient /etc/araddclient.conf
    echo "Sleeping for ${sleep_for} seconds..."
    sleep $sleep_for
done