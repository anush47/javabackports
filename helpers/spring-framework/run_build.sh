#!/bin/bash
# This script builds the Docker image and compiles the code.
set -e # Exit on error

echo "--- Building code for ${COMMIT_SHA:0:7} ---"

echo "--- Changing directory to ${PROJECT_DIR} ---"
cd "${PROJECT_DIR}"

echo "--- Checking out commit... ---"
git checkout -f ${COMMIT_SHA}
git clean -fd

# Create persistent Gradle cache volumes if they don't exist
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

${DOCKER_CMD} volume create gradle-cache-spring 2>/dev/null || true
${DOCKER_CMD} volume create gradle-wrapper-spring 2>/dev/null || true

echo "--- Building Docker image... ---"

# Detect Gradle version and choose appropriate Java version
if [ -f "gradle/wrapper/gradle-wrapper.properties" ]; then
    GRADLE_URL=$(grep "distributionUrl" gradle/wrapper/gradle-wrapper.properties)
    # Extract version like 8.5, 7.6, etc.
    GRADLE_VER=$(echo $GRADLE_URL | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    echo "Detected Gradle version: $GRADLE_VER"
    
    # Logic for Java version
    # Gradle 8.5+ support Java 21
    # Gradle 7.3+ support Java 17
    # Gradle < 7.3 usually Java 11 or 8
    
    MAJOR=$(echo $GRADLE_VER | cut -d. -f1)
    MINOR=$(echo $GRADLE_VER | cut -d. -f2)
    
    if [ "$MAJOR" -ge 9 ]; then
        JAVA_VERSION=21
    elif [ "$MAJOR" -eq 8 ]; then
        if [ "$MINOR" -ge 5 ]; then
             JAVA_VERSION=21
        else
             JAVA_VERSION=17
        fi
    elif [ "$MAJOR" -eq 7 ]; then
        if [ "$MINOR" -ge 3 ]; then
             JAVA_VERSION=17
        else
             JAVA_VERSION=11
        fi
    else
        # Gradle 6.x or older
        JAVA_VERSION=11
    fi
else
    echo "No gradle-wrapper.properties found, defaulting to Java 21"
    JAVA_VERSION=21
fi

echo "Selected JDK version: $JAVA_VERSION"

# -f points to the Dockerfile in our toolkit
# . (the context) is the PROJECT_DIR we just cd'd into
${DOCKER_CMD} build --build-arg JAVA_VERSION=${JAVA_VERSION} -t ${IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile .

echo "--- Setting cache permissions... ---"
${DOCKER_CMD} run --rm -u root \
    -v "gradle-cache-spring:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-spring:/home/gradle/.gradle/wrapper" \
    -v "${BUILD_DIR}:/repo/build" \
    ${IMAGE_TAG} \
    chown -R 1000:1000 /home/gradle/.gradle/caches /home/gradle/.gradle/wrapper /repo/build

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
