# Apache Flink helper image (Maven-based)
FROM eclipse-temurin:11-jdk

# ---- system packages --------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    maven \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

# Add the repo directory as a "safe directory" for Git
RUN git config --global --add safe.directory /repo

# ---- Git LFS setup ----------------------------------------------------
RUN git lfs install --system
