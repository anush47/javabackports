#!/bin/bash
set -e

echo "=== Building CrateDB with Maven ==="

# Determine which Maven command to use
if [ -f "mvnw" ]; then
    chmod +x mvnw
    MVN_CMD="./mvnw"
else
    MVN_CMD="mvn"
fi

echo "Using Maven command: $MVN_CMD"

# Clean and build, skipping tests
$MVN_CMD clean install -DskipTests -T 1C

echo "--- Build complete ---"

# Create output directory
mkdir -p /repo/build_outputs/build

# Copy build artifacts (for reference, though not strictly needed)
echo "--- Build artifacts location: target/ directories ---"
