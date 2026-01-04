#!/bin/bash
set -e

echo "Building document-upload Lambda..."

# Install dependencies
npm install --production

# Create deployment package
rm -f document-upload.zip
zip -r document-upload.zip . -x "*.git*" "build.sh" "*.zip"

echo "✓ Built document-upload.zip ($(du -h document-upload.zip | cut -f1))"
