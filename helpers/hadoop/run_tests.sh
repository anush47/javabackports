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
    # Check if we are in Granular Mode (targets contain ':')
    if [[ "${TEST_TARGETS}" == *":"* ]]; then
        echo "--- Detected Granular Test Targets ---"
        MODULES=""
        CLASSES=""
        
        # Split by space
        for target in ${TEST_TARGETS}; do
            # Format: module:class
            if [[ "$target" == *":"* ]]; then
                MOD=$(echo "$target" | cut -d':' -f1)
                CLS=$(echo "$target" | cut -d':' -f2)
                
                MODULES="${MODULES},${MOD}"
                CLASSES="${CLASSES},${CLS}"
            else
                # Fallback if mixed (shouldn't happen with current logic but safe to handle)
                MODULES="${MODULES},${target}"
            fi
        done
        
        # Clean up leading commas
        MODULES=$(echo "${MODULES}" | sed 's/^,//')
        CLASSES=$(echo "${CLASSES}" | sed 's/^,//')
        
        # Deduplicate modules (Maven doesn't like duplicates in -pl sometimes?)
        # Actually tr/sort/uniq is easier
        MODULES=$(echo "${MODULES}" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
        
        MAVEN_ARGS="-pl ${MODULES} -Dtest=${CLASSES} -am"
    else
        echo "--- Detected Module-Level Targets ---"
        # Run tests ONLY for the affected modules
        # Replace spaces with commas for Maven -pl flag
        COMMA_TARGETS=$(echo "${TEST_TARGETS}" | tr ' ' ',')
        MAVEN_ARGS="-pl ${COMMA_TARGETS} -am"
    fi
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