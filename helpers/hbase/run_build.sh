#!/bin/bash
# This script builds the Docker image and compiles HBase code.
set -e # Exit on error

echo "--- Building code for ${COMMIT_SHA:0:7} ---"

# Create persistent Maven cache volume
docker volume create maven-cache-hbase 2>/dev/null || true

echo "--- Building Docker image... ---"
docker build -t ${IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile ${TOOLKIT_DIR}

echo "--- Preparing build directory... ---"
# Copy source code to BUILD_DIR
cp -r "${PROJECT_DIR}/." "${BUILD_DIR}/"

echo "--- Compiling... ---"
# Build without tests, skip documentation and code quality checks
BUILD_COMMAND="git checkout -f ${COMMIT_SHA} && \
  mvn clean install -DskipTests \
    -Dmaven.javadoc.skip=true \
    -Dcheckstyle.skip=true \
    -Dfindbugs.skip=true \
    -Dspotbugs.skip=true \
    -Denforcer.skip=true"

if docker run --rm \
    --dns=8.8.8.8 \
    -v "${BUILD_DIR}:/repo" \
    -v "maven-cache-hbase:/root/.m2" \
    -w /repo \
    ${IMAGE_TAG} \
    bash -c "rm -rf /root/.m2/repository/org/apache/hbase && ${BUILD_COMMAND}"; then
    echo "Success" > $BUILD_STATUS_FILE
else
    echo "Fail" > $BUILD_STATUS_FILE
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"
