#!/bin/bash
# This script uses a "golden" cache that gets copied for each commit
set -e

echo "--- Building code for ${COMMIT_SHA:0:7} ---"

DOCKER_CMD="docker"
if ! docker info > /dev/null 2>&1; then
    if sudo docker info > /dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi
fi

# Golden cache that accumulates knowledge
GOLDEN_CACHE="gradle-cache-ls-golden"
${DOCKER_CMD} volume create ${GOLDEN_CACHE} 2>/dev/null || true

# Commit-specific cache
COMMIT_SHORT="${COMMIT_SHA:0:12}"
COMMIT_CACHE="gradle-cache-ls-${COMMIT_SHORT}"

# Check if commit cache exists, if not, seed it from golden
if ! ${DOCKER_CMD} volume inspect ${COMMIT_CACHE} > /dev/null 2>&1; then
    echo "--- Creating cache for ${COMMIT_SHORT} (seeded from golden)... ---"
    ${DOCKER_CMD} volume create ${COMMIT_CACHE}
    
    # Copy golden cache to new commit cache
    ${DOCKER_CMD} run --rm \
        -v "${GOLDEN_CACHE}:/source" \
        -v "${COMMIT_CACHE}:/dest" \
        alpine \
        sh -c "cp -a /source/. /dest/ 2>/dev/null || true"
fi

# Shared wrapper
${DOCKER_CMD} volume create gradle-wrapper-ls 2>/dev/null || true

# Build base image
BASE_IMAGE_TAG="logstash-builder:latest"
if ! ${DOCKER_CMD} image inspect ${BASE_IMAGE_TAG} > /dev/null 2>&1; then
    ${DOCKER_CMD} build -t ${BASE_IMAGE_TAG} -f ${TOOLKIT_DIR}/Dockerfile ${PROJECT_DIR}
fi

# Set permissions
${DOCKER_CMD} run --rm -u root \
    -v "${COMMIT_CACHE}:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
    ${BASE_IMAGE_TAG} \
    chown -R 1000:1000 /home/gradle/.gradle 2>/dev/null || true

cd "${PROJECT_DIR}"
git checkout -f ${COMMIT_SHA}

echo "--- Compiling code... ---"

GRADLE_TASKS="classes"
if [ "${TEST_TARGETS}" != "NONE" ] && [ "${TEST_TARGETS}" != "ALL" ]; then
    MODULES=$(echo "${TEST_TARGETS}" | tr ' ' '\n' | cut -d':' -f1 | sort -u | tr '\n' ' ')
    if [ -n "$MODULES" ]; then
        GRADLE_TASKS=$(echo "$MODULES" | sed 's/\([^ ]*\)/:\1:classes/g')
    fi
fi

if ${DOCKER_CMD} run --rm \
    --dns=8.8.8.8 \
    -u 1000:1000 \
    -v "${COMMIT_CACHE}:/home/gradle/.gradle/caches" \
    -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    ${BASE_IMAGE_TAG} \
    bash -c "git config --global --add safe.directory /repo && \
             ./gradlew ${GRADLE_TASKS} -Dbuild.docker=false --no-daemon --parallel"; then
    
    if [ "${TEST_TARGETS}" != "NONE" ]; then
        ${DOCKER_CMD} run --rm \
            --dns=8.8.8.8 \
            -u 1000:1000 \
            -v "${COMMIT_CACHE}:/home/gradle/.gradle/caches" \
            -v "gradle-wrapper-ls:/home/gradle/.gradle/wrapper" \
            -v "${PROJECT_DIR}:/repo" \
            -w /repo \
            ${BASE_IMAGE_TAG} \
            ./gradlew testClasses -Dbuild.docker=false --no-daemon --parallel || true
    fi
    
    # After successful build, update golden cache
    echo "--- Updating golden cache... ---"
    ${DOCKER_CMD} run --rm \
        -v "${COMMIT_CACHE}:/source" \
        -v "${GOLDEN_CACHE}:/dest" \
        alpine \
        sh -c "cp -au /source/. /dest/ 2>/dev/null || true"
    
    echo "Success" > $BUILD_STATUS_FILE
else
    echo "Fail" > $BUILD_STATUS_FILE
fi

# Cleanup: keep last 5 commit caches
CACHE_VOLUMES=$(${DOCKER_CMD} volume ls -q | grep "^gradle-cache-ls-" | grep -v "golden" | sort -r)
echo "$CACHE_VOLUMES" | tail -n +6 | xargs -r ${DOCKER_CMD} volume rm 2>/dev/null || true

echo "--- Build complete for ${COMMIT_SHA:0:7} ---"