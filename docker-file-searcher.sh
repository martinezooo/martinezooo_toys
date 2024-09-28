#!/bin/bash

echo $'============ Docker File Searcher ============\n'
echo $'The script will search a file using the basic unix tools.\n'

# Check if the user provided input
if [ -z "$1" ]; then
    echo "Error, no input provided."
    echo "Usage: docker-grepsearcher.sh <file_name>"
    exit 1
else
    file=$1
    echo "Searching for file: $file"
    
    # Loop through all running Docker containers
    for container in $(docker ps -q); do
        echo -e "Searching in container: $container"
        
        # Execute the search inside the container
        docker exec "$container" sh -c "ls -R / 2>/dev/null" | awk -v search="$file" '
        {
            if ($0 ~ /:$/) {
                # If the line ends with ':', it is a directory
                current_dir = substr($0, 1, length($0)-1)  # Remove the ':'
            } else if ($0 ~ search) {
                # If the line matches the search term, print the full path
                print current_dir "/" $0
            }
        }'
        
    done
fi
