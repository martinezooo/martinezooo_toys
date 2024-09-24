#!/bin/bash

# Global for HTTP/HTTPS
http_containers=""

# Function to check if an exposed port is running an HTTP/HTTPS server using curl -k
check_http_server() {
    local ip=$1
    local port=$2

    # First try with http
    http_status=$(curl -s -k -o /dev/null -w "%{http_code}" http://$ip:$port 2>&1)

    # If the status code is valid, treat it as HTTP/HTTPS server
    if [[ "$http_status" -ge 200 && "$http_status" -lt 600 ]]; then
        echo "HTTP server detected on http://$ip:$port (status code: $http_status)"
        http_containers+="http://$ip:$port"$'\n'
        return 0
    fi

    # If no valid response from http, try https
    https_status=$(curl -s -k -o /dev/null -w "%{http_code}" https://$ip:$port 2>&1)

    if [[ "$https_status" -ge 200 && "$https_status" -lt 600 ]]; then
        echo "HTTPS server detected on https://$ip:$port (status code: $https_status)"
        http_containers+="https://$ip:$port"$'\n'
        return 0
    fi

    # If both checks failed, assume no HTTP/HTTPS server
    echo "No HTTP/HTTPS server detected on $ip:$port (connection refused or no response)"
    return 1
}

# Function to inspect container for configuration details and mounted directories
inspect_container() {
    local container_id=$1
    local container_name=$2

    echo "Inspecting container: $container_name ($container_id)"

    # Check (WorkingDir)
    echo "Checking working directory..."
    working_dir=$(docker inspect --format='{{.Config.WorkingDir}}' "$container_id")
    if [[ -n "$working_dir" ]]; then
        echo "Working directory: $working_dir"
    else
        echo "No specific working directory set."
    fi

    # Sprawdzenie polecenia uruchamianego podczas startu (Cmd)
    echo "Checking start command (CMD)..."
    docker inspect --format='Cmd: {{json .Config.Cmd}}' "$container_id"

    # Check entrypoint
    echo "Checking entrypoint..."
    docker inspect --format='Entrypoint: {{json .Config.Entrypoint}}' "$container_id"

    # Check mounted dirs
    echo "Mounted directories that are accessible from the outside:"
    mounts=$(docker inspect $container_id | grep -i "Destination" | awk '{print $2}' | tr -d '",')

    if [ -z "$mounts" ]; then
        echo "No mounted directories."
    else
        for mount in $mounts; do
            echo "Directory $mount (recursive):"
            
            # Check if the directory exists and display its contents recursively
            docker exec $container_id ls -laR $mount 2>/dev/null
            
            if [ $? -ne 0 ]; then
                echo "Directory does not exist or access is denied."
            else
                echo "Mounted directory $mount is available."
                # Store mounted directory details for potential download
                echo "$container_name:$mount" >> mounted_dirs.txt
            fi
            echo ""
        done
    fi

    echo "======================================"
}

# Function to download mounted directories if user agrees
download_mounted_directories() {
    if [ -f mounted_dirs.txt ]; then
        read -p "Would you like to download the mounted directories and the files from Entrypoint/Cmd? (yes/no): " choice
        if [[ "$choice" == "yes" || "$choice" == "y" ]]; then
            mkdir -p onlyhttp_mounted
            while read -r line; do
                container_name=$(echo "$line" | awk -F':' '{print $1}')
                mount_path=$(echo "$line" | awk -F':' '{print $2}')
                
                echo "Downloading mounted directory $mount_path from container $container_name..."
                
                # Create a folder for the container in onlyhttp_mounted
                mkdir -p "onlyhttp_mounted/$container_name"
                
                # Copy the contents of the mounted directory from the container
                docker cp "$container_name:$mount_path" "onlyhttp_mounted/$container_name/" 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    echo "Downloaded $mount_path from $container_name."
                else
                    echo "Failed to download $mount_path from $container_name."
                fi
                
                # Download entrypoint and cmd info
                entrypoint=$(docker inspect "$container_name" | grep '"Entrypoint"' -A 1 | grep -o '"/[^"]*"' | tr -d '"')
                cmd=$(docker inspect "$container_name" | grep '"Cmd"' -A 1 | grep -o '"/[^"]*"' | tr -d '"')

                # Download files mentioned in Entrypoint
                if [ -n "$entrypoint" ]; then
                    echo "Downloading Entrypoint file(s) from container $container_name..."
                    for file in $entrypoint; do
                        # Check if the file is a valid path and copy it
                        if [[ $file == /* ]]; then
                            docker cp "$container_name:$file" "onlyhttp_mounted/$container_name/" 2>/dev/null
                            if [ $? -eq 0 ]; then
                                echo "Downloaded $file from Entrypoint."
                            else
                                echo "Failed to download $file from Entrypoint."
                            fi
                        else
                            echo "Skipping non-path Entrypoint command: $file"
                        fi
                    done
                else
                    echo "No Entrypoint defined for $container_name."
                fi

                # Download files mentioned in Cmd
                if [ -n "$cmd" ]; then
                    echo "Downloading Cmd file(s) from container $container_name..."
                    for file in $cmd; do
                        # Check if the file is a valid path and copy it
                        if [[ $file == /* ]]; then
                            docker cp "$container_name:$file" "onlyhttp_mounted/$container_name/" 2>/dev/null
                            if [ $? -eq 0 ]; then
                                echo "Downloaded $file from Cmd."
                            else
                                echo "Failed to download $file from Cmd."
                            fi
                        else
                            echo "Skipping non-path Cmd command: $file"
                        fi
                    done
                else
                    echo "No Cmd defined for $container_name."
                fi
                
            done < mounted_dirs.txt
            echo "All selected directories and Entrypoint/Cmd files have been downloaded to the onlyhttp_mounted directory."
        else
            echo "Skipping download of mounted directories and Entrypoint/Cmd files."
        fi
        # Clean up
        rm mounted_dirs.txt
    else
        echo "No mounted directories found to download."
    fi
}




# Get a list of all running containers
containers=$(docker ps --format "{{.ID}} {{.Names}}")

# For each container
while read -r container_id container_name; do
    echo "Checking container: $container_name ($container_id)"
    
    # Check which ports are exposed
    ports=$(docker port $container_id)
    echo "Exposed ports: $ports"

    # Check for any HTTP/HTTPS server on the exposed ports
    while read -r port_mapping; do
        # Extract IP and port from the port mapping
        ip_port=$(echo "$port_mapping" | awk -F' -> ' '{print $2}')
        ip=$(echo "$ip_port" | awk -F':' '{print $1}')
        port=$(echo "$ip_port" | awk -F':' '{print $2}')

        # Check if IP and port are valid before continuing
        if [[ -z "$ip" || -z "$port" ]]; then
            echo "Skipping invalid port mapping: $port_mapping"
            continue
        fi

        echo "Checking if port $port on IP $ip is running an HTTP/HTTPS server..."

        # Use curl -k to check if the server is HTTP/HTTPS
        if check_http_server "$ip" "$port"; then
            # If an HTTP/HTTPS server is detected, check for webroot or codebase
            inspect_container "$container_id" "$container_name"
        fi
    done <<< "$ports"

    echo "======================================"
done <<< "$containers"

# Wypisz wszystkie znalezione serwery HTTP/HTTPS
if [[ -n "$http_containers" ]]; then
    echo "Detected HTTP/HTTPS servers:"
    echo "$http_containers"
else
    echo "No HTTP/HTTPS servers detected in any container."
fi

# ASK USER 
download_mounted_directories
