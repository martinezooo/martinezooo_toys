#!/bin/bash

echo $'============Docker file searcher============\n'
echo $'The script will Grep user input recursively'
if [ -z $1]; then
    echo "Error, no input provided."
    echo "Usage: docker-grepsearcher.sh <name>"
    exit 1
else
    file = $1
    for container in $(docker ps -q); do
        echo "Searching for $file in container: $container"
        docker exec $container sh -c 'ls -R / 2>/dev/null | grep -s '$file
    done
fi
