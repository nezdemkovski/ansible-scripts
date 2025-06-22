#!/bin/bash

# Script to encrypt all .env files in docker/* directories
# Usage: ./encrypt-all-envs.sh

set -e  # Exit on any error

echo "🔐 Starting encryption of all .env files in docker/ directories..."
echo ""

# Counter for tracking progress
total_files=0
encrypted_files=0
skipped_files=0

# Find all .env files in docker subdirectories
while IFS= read -r -d '' env_file; do
    total_files=$((total_files + 1))
    
    # Get the directory and filename
    dir=$(dirname "$env_file")
    filename=$(basename "$env_file")
    
    # Check if .env.enc already exists
    enc_file="${env_file}.enc"
    
    if [[ -f "$enc_file" ]]; then
        echo "⚠️  Skipping $env_file (encrypted version already exists)"
        skipped_files=$((skipped_files + 1))
        continue
    fi
    
    echo "🔒 Encrypting: $env_file"
    
    # Run SOPS encryption
    if sops -e "$env_file" > "$enc_file"; then
        echo "✅ Created: $enc_file"
        encrypted_files=$((encrypted_files + 1))
    else
        echo "❌ Failed to encrypt: $env_file"
        # Remove the failed .enc file if it was created
        [[ -f "$enc_file" ]] && rm "$enc_file"
    fi
    
    echo ""
    
done < <(find docker/ -name "*.env" -type f -print0)

echo "📊 Summary:"
echo "   Total .env files found: $total_files"
echo "   Successfully encrypted: $encrypted_files"
echo "   Skipped (already encrypted): $skipped_files"
echo ""

if [[ $encrypted_files -gt 0 ]]; then
    echo "🎉 Encryption completed successfully!"
else
    echo "ℹ️  No files were encrypted."
fi 