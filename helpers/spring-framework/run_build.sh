#!/bin/bash
set -e

echo "--- Building Spring Framework for ${COMMIT_SHA:0:7} ---"

cd "${PROJECT_DIR}"

echo "--- Checking out commit... ---"
git checkout -f ${COMMIT_SHA}
git clean -fd

# Create persistent Gradle cache volumes
docker volume create gradle-cache-spring 2>/dev/null || true
docker volume create gradle-wrapper-spring 2>/dev/null || true

echo "--- Building Docker image with adaptive Java version... ---"

# Detect Gradle version and choose appropriate Java version
JAVA_VERSION=17
if [ -f "gradle/wrapper/gradle-wrapper.properties" ]; then
    GRADLE_URL=$(grep "distributionUrl" gradle/wrapper/gradle-wrapper.properties 2>/dev/null || echo "")
    if [ ! -z "$GRADLE_URL" ]; then
        GRADLE_VER=$(echo $GRADLE_URL | grep -oE '[0-9]+\.[0-9]+' | head -1)
        echo "Detected Gradle version: $GRADLE_VER"
        
        MAJOR=$(echo $GRADLE_VER | cut -d. -f1)
        MINOR=$(echo $GRADLE_VER | cut -d. -f2)
        
        if [ "$MAJOR" -ge 8 ]; then
            JAVA_VERSION=17
        else
            JAVA_VERSION=11
        fi
    fi
fi

echo "Using Java version: $JAVA_VERSION"

# Build the Docker image with detected Java version
docker build --build-arg JAVA_VERSION=${JAVA_VERSION} -t ${IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile ${TOOLKIT_DIR}

echo "--- Running Gradle build (compile only, no tests) ---"

# Run build in Docker with the source code mounted
if docker run --rm \
    -u 1000:1000 \
    -v "${PROJECT_DIR}:/repo" \
    -v "gradle-cache-spring:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-spring:/home/gradle/.gradle/wrapper" \
    -w /repo \
    ${IMAGE_TAG} \
    bash -c "set -e; \
             git config --global --add safe.directory /repo; \
             git checkout -f ${COMMIT_SHA}; \
             ./gradlew clean build -x test --no-daemon -Dorg.gradle.jvmargs='-Xmx4g'"; then
    echo "Success" > "${BUILD_STATUS_FILE}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"

echo "--- Compiling and preparing for tests... ---"
# Spring build: classes testClasses
if ${DOCKER_CMD} run --rm \
    --dns=8.8.8.8 \
    -u 1000:1000 \
    -v "gradle-cache-spring:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-spring:/home/gradle/.gradle/wrapper" \
    -v "${BUILD_DIR}:/repo/build" \
    ${IMAGE_TAG} \
    ./gradlew classes testClasses -Dbuild.docker=false --continue; then
    echo "Success" > $BUILD_STATUS_FILE
else
    echo "Fail" > $BUILD_STATUS_FILE
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"
