#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Target: ${TEST_TARGETS}"

# 1. Reconstruct the Docker Image Tag
IMAGE_TAG="${IMAGE_TAG:-kafka-${BUILD_TYPE}-${COMMIT_SHA:0:7}}"

echo "--- Using Docker Image: ${IMAGE_TAG} ---"

# 2. Configure Test Command
if [ "${TEST_TARGETS}" == "ALL" ]; then
    GRADLE_CMD="./gradlew test"
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    GRADLE_CMD="./gradlew ${TEST_TARGETS}"
fi

# Determine if we need sudo for docker
DOCKER_CMD="docker"
if ! docker info > /dev/null 2>&1; then
    if sudo docker info > /dev/null 2>&1; then
        echo "Docker requires sudo. Using 'sudo docker'."
        DOCKER_CMD="sudo docker"
    else
        echo "Warning: Docker command failed and sudo check failed. Continuing with 'docker' but expect errors."
    fi
fi

# 3. Run Tests in Docker
# Create persistent Gradle cache volumes if they don't exist
${DOCKER_CMD} volume create gradle-cache-kafka 2>/dev/null || true
${DOCKER_CMD} volume create gradle-wrapper-kafka 2>/dev/null || true

echo "--- Executing: ${GRADLE_CMD} ---"

# Note: The Dockerfile for Kafka already sets WORKDIR /repo and user 'gradle'
if ${DOCKER_CMD} run --rm \
    --dns=8.8.8.8 \
    -u 1000:1000 \
    -v "gradle-cache-kafka:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-kafka:/home/gradle/.gradle/wrapper" \
    -v "${BUILD_DIR}:/repo/build" \
    "${IMAGE_TAG}" \
    bash -c "${GRADLE_CMD}; \
    GRADLE_EXIT_CODE=\$?; \
    mkdir -p /repo/build/all-test-results; \
    find . -name 'TEST-*.xml' -exec cp {} /repo/build/all-test-results/ \;; \
    exit \$GRADLE_EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "❌ Tests Failed"
    exit 1
fi