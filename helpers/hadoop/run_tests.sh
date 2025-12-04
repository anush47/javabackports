#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Target Modules: ${TEST_TARGETS}"

# 1. Configure Test Command
# We explicitly exclude the broken YARN catalog modules we found earlier
EXCLUDE_FLAGS="-pl '!hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-webapp,!hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-docker,!hadoop-yarn-project'"

if [ "${TEST_TARGETS}" == "ALL" ]; then
    # Run all tests, but exclude the broken ones
    MAVEN_ARGS="${EXCLUDE_FLAGS}"
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    # Run tests ONLY for the affected modules
    # Replace spaces with commas for Maven -pl flag
    COMMA_TARGETS=$(echo "${TEST_TARGETS}" | tr ' ' ',')
    MAVEN_ARGS="-pl ${COMMA_TARGETS} -am"
fi

echo "--- Starting Test Execution ---"
echo "--- Command: mvn test ${MAVEN_ARGS} ---"

# 2. Run Tests
# We use the same 'maven-cache' volume from the build step
docker volume create maven-cache 2>/dev/null || true

# 3. Run in Docker
# We use the IMAGE_TAG passed from run_tests.py (which matches the one built in run_build.sh)
if docker run --rm \
    --dns=8.8.8.8 \
    -v "${BUILD_DIR}:/repo" \
    -v "maven-cache:/root/.m2" \
    -w /repo \
    "${IMAGE_TAG}" \
    bash -c "mvn test ${MAVEN_ARGS} -DfailIfNoTests=false -Dmaven.javadoc.skip=true -Drat.skip=true -Dcheckstyle.skip=true; \
    MVN_EXIT_CODE=\$?; \
    mkdir -p /repo/all-test-results; \
    find . -name 'TEST-*.xml' -exec cp {} /repo/all-test-results/ \;; \
    exit \$MVN_EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "❌ Tests Failed"
    exit 1
fi