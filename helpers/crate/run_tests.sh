#!/bin/bash
set -e

TEST_TARGETS="$@"

echo "=== Running CrateDB Tests ==="
echo "Target: $TEST_TARGETS"

# Ensure Maven wrapper is executable
chmod +x mvnw

# Create output directory
mkdir -p /repo/build_outputs/build

# Run tests with specified targets
if [ -z "$TEST_TARGETS" ]; then
    echo "--- No test targets specified, running all tests ---"
    ./mvnw test -T 1C
else
    echo "--- Executing: ./mvnw $TEST_TARGETS ---"
    ./mvnw $TEST_TARGETS
fi

TEST_EXIT_CODE=$?

# Copy test reports using rsync
echo "--- Copying test reports with rsync ---"
rsync -avz --prune-empty-dirs --include='*/' --include='*.xml' --exclude='*' \
    --include='**/target/surefire-reports/**' \
    /repo/ /repo/build_outputs/build/

echo "--- Test results copied ---"

# Check if tests passed
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ Tests Passed"
else
    echo "❌ Tests Failed (exit code: $TEST_EXIT_CODE)"
fi

exit $TEST_EXIT_CODE
