#!/bin/bash

# Check if directory is provided as argument
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/directory"
  exit 1
fi

directory=$1
output_file="paths.txt"

# Clear or create output file
> $output_file

# Function to extract paths and URLs from files
extract_paths_and_urls() {
  local file=$1
  # Use grep to search for paths and URLs and append to output_file
  grep -Eo "(\/[a-zA-Z0-9_\/\.\-]+|https?:\/\/[a-zA-Z0-9_\-\.]+\.[a-zA-Z]{2,3}(\/\S*)?)" "$file" >> "$output_file"
}

# Recursively find all files in the given directory and process them
find "$directory" -type f | while read -r file; do
  echo "Processing $file..."
  extract_paths_and_urls "$file"
done

echo "All paths and URLs have been extracted to $output_file"
