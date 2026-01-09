#!/bin/bash
# Optimized Doris build script with permission fix
set -euo pipefail

echo "=== Building Doris for commit ${COMMIT_SHA:0:7} ==="

# Initialize build exit code
BUILD_EXIT_CODE=0

cd "${PROJECT_DIR}"

# FIX: Use Docker as root to forcefully clean and fix permissions
echo "=== Cleaning Docker-created files and fixing permissions ==="
docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -w /repo \
    --user root \
    ${BUILDER_IMAGE_TAG} \
    bash -c "git config --global --add safe.directory /repo && git clean -fdx && chown -R $(id -u):$(id -g) /repo" || true

# Now checkout can succeed
echo "=== Checking out commit ${COMMIT_SHA} ==="
git checkout -f ${COMMIT_SHA}

# Create Maven cache volume (reuse across builds)
docker volume create maven-repo 2>/dev/null || true

echo "=== Running standard Maven build ==="

    # Run Maven build
    # Pointing to fe/pom.xml as Apache Doris Java components are mainly in FE
    # We set DORIS_HOME just in case
    docker run --rm \
        -v "${PROJECT_DIR}:/repo" \
        -v "maven-repo:/root/.m2/repository" \
        -w /repo \
        -e DORIS_HOME=/repo \
        ${BUILDER_IMAGE_TAG} \
        bash -c "
            ls -la;
            # Load Doris build environment (matches official build.sh)
            if [ -f env.sh ]; then 
                echo 'Sourcing env.sh...'; 
                . ./env.sh; 
            else 
                echo 'env.sh NOT found'; 
            fi;
            if [ -f generated-source.sh ]; then 
                echo 'Found generated-source.sh';
                thrift --version || echo 'Thrift not found';
                echo 'Running generated-source.sh...'; 
                bash generated-source.sh noclean; 
            else
                echo 'generated-source.sh NOT found';
            fi;
            if [ -f fe/pom.xml ]; then 
                mvn -f fe/pom.xml clean install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Dforbiddenapis.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C; 
            else 
                echo 'No fe/pom.xml found, checking root...'; 
                mvn clean install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -Dpmd.skip=true -Dforbiddenapis.skip=true -Denforcer.skip=true -Drat.skip=true -T 1C; 
            fi" \
        || BUILD_EXIT_CODE=$?

# Save build status
if [ ${BUILD_EXIT_CODE} -eq 0 ]; then
    echo "Success" > "${BUILD_STATUS_FILE}"
    echo "✅ Build succeeded for ${COMMIT_SHA:0:7}"
else
    echo "Fail" > "${BUILD_STATUS_FILE}"
    echo "❌ Build failed for ${COMMIT_SHA:0:7}"
fi

echo "=== Build finished for ${COMMIT_SHA:0:7} ==="
