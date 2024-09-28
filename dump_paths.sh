#!/bin/bash

# Check if directory is provided as argument
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/directory [keyword] [extension]"
  echo "Example: $0 /path/to/directory keyword .txt"
  echo "Or: $0 /path/to/directory '' .txt"
  exit 1
fi

directory=$1
keyword=$2
extension=$3
output_file="/tmp/paths.txt"

# Clear or create output file
> $output_file

# Function to extract paths and URLs from files
extract_paths_and_urls() {
  local file=$1
  # Use grep to search for paths and URLs, normalize slashes, remove duplicates, and append to output_file
  grep -Eo "(\/[a-zA-Z0-9_\/\.\-]+|https?:\/\/[a-zA-Z0-9_\-\.]+\.[a-zA-Z]{2,3}(\/\S*)?)" "$file" | \
  sed 's#//*#/#g' | sed 's#\\##g' | sort | uniq >> "$output_file"
}

# Function to process all files or files with specific extension
process_files() {
  find "$directory" -type f $1 | while read -r file; do
    if [[ -n "$keyword" ]]; then
      # Search for the keyword in the file
      if grep -q "$keyword" "$file"; then
        echo "Keyword '$keyword' found in $file."
        echo "Extracting paths and URLs from $file..."
        extract_paths_and_urls "$file"
      fi
    else
      # Process all files without filtering by keyword
      echo "Processing $file..."
      extract_paths_and_urls "$file"
    fi
  done
}

# Option 1: If an extension is provided, scan only files with that extension
if [[ -n "$extension" ]]; then
  echo "Scanning files with extension $extension..."
  process_files "-name *$extension"

# Option 2: If no extension is provided but a keyword is, scan all files for the keyword
elif [[ -n "$keyword" ]]; then
  echo "Scanning all files for keyword '$keyword'..."
  process_files ""

# Option 3: If no keyword or extension is provided, scan all files
else
  echo "Scanning all files for paths and URLs..."
  process_files ""
fi

# Remove duplicate entries from output file and ensure clean formatting
sort "$output_file" | uniq > "${output_file}.tmp" && mv "${output_file}.tmp" "$output_file"

echo "All unique paths and URLs have been extracted to $output_file"
