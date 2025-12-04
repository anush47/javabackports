#!/bin/bash
set -e

echo "=== Running Tests for ${COMMIT_SHA:0:7} ==="
echo "Targets: ${TEST_TARGETS}"

# 1. Configure Test Command
if [ "${TEST_TARGETS}" == "ALL" ]; then
    # Run standard unit tests for everything
    MAVEN_ARGS=""
elif [ "${TEST_TARGETS}" == "NONE" ]; then
    echo "No relevant source code changes found. Skipping tests."
    exit 0
else
    # TEST_TARGETS is a space-separated list of "module:class"
    
    MODULES=""
    TESTS=""
    
    # Split by space
    for target in ${TEST_TARGETS}; do
        # Split by colon
        mod="${target%%:*}"
        cls="${target#*:}"
        
        # Append to lists (comma separated)
        if [ -z "$MODULES" ]; then
            MODULES="$mod"
        else
            # Avoid duplicates in modules list
            if [[ ",$MODULES," != *",$mod,"* ]]; then
                MODULES="$MODULES,$mod"
            fi
        fi
        
        if [ -z "$TESTS" ]; then
            TESTS="$cls"
        else
            TESTS="$TESTS,$cls"
        fi
    done
    
    MAVEN_ARGS="-pl ${MODULES} -Dtest=${TESTS}"
fi

echo "--- Starting Test Execution ---"
echo "--- Command: mvn test ${MAVEN_ARGS} ---"

# 2. Run Tests
docker volume create maven-repo 2>/dev/null || true

if docker run --rm \
    -v "${PROJECT_DIR}:/repo" \
    -v "maven-repo:/root/.m2/repository" \
    -v "/var/run/docker.sock:/var/run/docker.sock" \
    -w /repo \
    "${BUILDER_IMAGE_TAG}" \
    bash -c "git checkout -f ${COMMIT_SHA} && \
             mvn test ${MAVEN_ARGS} -DfailIfNoTests=false -Denforcer.skip=true -Dskip.yarn -Dskip.npm -Dskip.installnodenpm -Dmaven.antrun.skip=true -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true; \
             MVN_EXIT_CODE=\$?; \
             mkdir -p /repo/build/all-test-results; \
             find . -name 'TEST-*.xml' -exec cp {} /repo/build/all-test-results/ \;; \
             exit \$MVN_EXIT_CODE"; then
    
    echo "✅ Tests Passed"
    exit 0
else
    echo "❌ Tests Failed"
    exit 1
fi
