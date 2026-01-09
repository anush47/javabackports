# Use the official Temurin 17 image
FROM eclipse-temurin:17-jdk

# ---- system packages --------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        git \
        git-lfs \
        maven \
        python3 \
        thrift-compiler \
        protobuf-compiler \
        && rm -rf /var/lib/apt/lists/*

# Ensure `python` and `thrift` binaries are available, as Doris scripts expect these names
RUN if [ -x /usr/bin/python3 ] && [ ! -x /usr/bin/python ]; then \
            ln -s /usr/bin/python3 /usr/bin/python; \
        fi && \
        if [ -x /usr/bin/thrift-compiler ] && [ ! -x /usr/bin/thrift ]; then \
            ln -s /usr/bin/thrift-compiler /usr/bin/thrift; \
        fi

# Hint Doris build scripts to use python3
ENV DORIS_BUILD_PYTHON_VERSION=python3

# ---- Boot JDK setup -------------------------------------------------
ENV BOOT_JDK=/opt/java/openjdk
RUN echo "Boot JDK is at ${BOOT_JDK}" && ${BOOT_JDK}/bin/java -version

# --- Switch to root user to fix all permission errors ---
WORKDIR /repo

# Add the repo directory as a "safe directory" for Git
RUN git config --global --add safe.directory /repo

# ---- Git LFS setup ----------------------------------------------------
RUN git lfs install --system
