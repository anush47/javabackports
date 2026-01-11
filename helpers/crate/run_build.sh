#!/bin/bash
set -e

echo "=== Building CrateDB with Maven ==="

# Ensure Maven wrapper is executable
chmod +x mvnw

# Clean and build, skipping tests
./mvnw clean install -DskipTests -T 1C

echo "--- Build complete ---"

# Create output directory
mkdir -p /repo/build_outputs/build

# Copy build artifacts (for reference, though not strictly needed)
echo "--- Build artifacts location: target/ directories ---"
