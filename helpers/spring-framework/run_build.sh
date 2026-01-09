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

# Fix permissions and create all required directories before running build
docker run --rm \
    --user root \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    ${IMAGE_TAG} \
    bash -c "set -e; \
             chown -R 1000:1000 /repo/.git 2>/dev/null || true; \
             mkdir -p /repo/.gradle /repo/build /repo/buildSrc/.gradle; \
             chown -R 1000:1000 /repo/.gradle /repo/build /repo/buildSrc; \
             echo '' > /repo/build/build-scan-uri.txt 2>/dev/null || true"

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
             export GRADLE_OPTS='-Dorg.gradle.internal.publish.checksums.insecure=true'; \
             ./gradlew clean build -x test --no-daemon \
               -Dorg.gradle.jvmargs='-XX:+IgnoreUnrecognizedVMOptions -XX:+UseG1GC -XX:+UseStringDeduplication' \
               --scan-off 2>/dev/null || ./gradlew clean build -x test --no-daemon"; then
    echo "Success" > "${BUILD_STATUS_FILE}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
fi

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"
