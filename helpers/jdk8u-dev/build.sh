#!/usr/bin/env bash
# This script runs INSIDE the Docker container
set -euo pipefail

echo "=== Building JDK for ${COMMIT_SHA:0:7} (Inside Container) ==="

# The Boot JDK and jtreg are provided by the Docker image's env variables
echo "Using Boot JDK: ${BOOT_JDK}"
echo "Using jtreg: ${JTREG_HOME}"

# Checkout the specific commit
echo "Checking out commit: ${COMMIT_SHA}"
git checkout -f "${COMMIT_SHA}"

# Use a shared build directory to enable incremental builds
export BUILD_DIR_ABS="/repo/build_shared"
echo "--- Using shared build directory for incremental builds: ${BUILD_DIR_ABS} ---"

# Check if we need to configure (only on first build or if configure changed)
NEED_CONFIGURE=false
if [ ! -f "${BUILD_DIR_ABS}/spec.gmk" ]; then
    echo "--- No existing spec.gmk found, will configure ---"
    NEED_CONFIGURE=true
    mkdir -p "${BUILD_DIR_ABS}"
fi

# 'cd' into the build directory
cd "${BUILD_DIR_ABS}"

if [ "${NEED_CONFIGURE}" = true ]; then
    echo "--- Configuring build from outside source dir... ---"
    
    # Note: --disable-warnings-as-errors does NOT exist in JDK 8
    bash ../configure \
        --with-boot-jdk="${BOOT_JDK}" \
        --with-jtreg="${JTREG_HOME}" \
        --enable-ccache \
        --with-debug-level=release \
        --with-native-debug-symbols=none \
        --disable-zip-debug-info
    
    echo "--- Patching spec.gmk to disable warnings-as-errors... ---"
    # JDK 8's build system hardcodes -Werror in many places
    # We need to remove it from the generated spec.gmk file
    if [ -f spec.gmk ]; then
        # Remove -Werror flags from all compiler flag variables
        sed -i 's/-Werror[^ ]*//g' spec.gmk
        sed -i 's/WARNINGS_ARE_ERRORS[[:space:]]*:=[[:space:]]*-Werror/WARNINGS_ARE_ERRORS :=/g' spec.gmk
        echo "--- spec.gmk patched ---"
    else
        echo "--- Warning: spec.gmk not found, skipping patch ---"
    fi
else
    echo "--- Skipping configure (using existing configuration for incremental build) ---"
fi

# Build the JDK incrementally
echo "--- Running incremental make... (Output will be in ${BUILD_DIR_ABS}) ---"

# For JDK 8, use 'all' target instead of 'images'
# Make will automatically detect what needs to be rebuilt
if make JOBS="${MAKE_JOBS:-$(nproc)}" all \
    COMPILER_WARNINGS_FATAL=false \
    WARNINGS_ARE_ERRORS="" \
    CFLAGS_WARNINGS_ARE_ERRORS=""; then
    echo "=== Build OK ==="
else
    echo "=== Build FAILED ==="
    exit 1
fi