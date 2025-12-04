#!/bin/bash
# This script builds the Docker image and compiles the code.
set -e # Exit on error

echo "--- Building code for ${COMMIT_SHA:0:7} ---"

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

# Create persistent volumes if they don't exist
${DOCKER_CMD} volume create gradle-cache-ls 2>/dev/null || true
${DOCKER_CMD} volume create gradle-wrapper-ls 2>/dev/null || true

# ============================================
# OPTIMIZATION 1: Build Docker image only once
# ============================================
# Check if base image already exists
BASE_IMAGE_TAG="logstash-builder:latest"

if ! ${DOCKER_CMD} image inspect ${BASE_IMAGE_TAG} > /dev/null 2>&1; then
    echo "--- Building Docker base image (one-time operation)... ---"
    ${DOCKER_CMD} build -t ${BASE_IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile ${PROJECT_DIR}
else
    echo "--- Using cached Docker base image ${BASE_IMAGE_TAG} ---"
fi

# Set cache permissions (only needed once, but harmless to repeat)
echo "--- Setting cache permissions... ---"
${DOCKER_CMD} run --rm -u root \
    -v "gradle-cache-ls:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
    ${BASE_IMAGE_TAG} \
    chown -R 1000:1000 /home/gradle/.gradle/caches /home/gradle/.gradle/wrapper 2>/dev/null || true

# ============================================
# OPTIMIZATION 2: Incremental compilation
# ============================================
echo "--- Changing directory to ${PROJECT_DIR} ---"
cd "${PROJECT_DIR}"

echo "--- Checking out commit ${COMMIT_SHA:0:7}... ---"
git checkout -f ${COMMIT_SHA}

echo "--- Compiling code... ---"
# Only compile production code first (faster if tests won't run)
# Mount the entire PROJECT_DIR to preserve build state between runs
if ${DOCKER_CMD} run --rm \
    --dns=8.8.8.8 \
    -u 1000:1000 \
    -v "gradle-cache-ls:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    ${BASE_IMAGE_TAG} \
    bash -c "git config --global --add safe.directory /repo && \
             ./gradlew classes -Dbuild.docker=false --no-daemon --parallel"; then
    
    # Only compile test classes if we'll actually run tests
    if [ "${TEST_TARGETS}" != "NONE" ]; then
        echo "--- Compiling test classes... ---"
        ${DOCKER_CMD} run --rm \
            --dns=8.8.8.8 \
            -u 1000:1000 \
            -v "gradle-cache-ls:/home/gradle/.gradle/caches" \
            -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
            -v "${PROJECT_DIR}:/repo" \
            -w /repo \
            ${BASE_IMAGE_TAG} \
            ./gradlew testClasses -Dbuild.docker=false --no-daemon --parallel || true
    fi
    
    echo "Success" > $BUILD_STATUS_FILE
else
    echo "Fail" > $BUILD_STATUS_FILE
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"