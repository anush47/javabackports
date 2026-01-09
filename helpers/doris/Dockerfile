# Use the official Temurin 17 image
FROM eclipse-temurin:17-jdk

# ---- system packages --------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    git-lfs \
    maven \
    && rm -rf /var/lib/apt/lists/*

# ---- Boot JDK setup -------------------------------------------------
ENV BOOT_JDK=/opt/java/openjdk
RUN echo "Boot JDK is at ${BOOT_JDK}" && ${BOOT_JDK}/bin/java -version

# --- Switch to root user to fix all permission errors ---
WORKDIR /repo

# Add the repo directory as a "safe directory" for Git
RUN git config --global --add safe.directory /repo

# ---- Git LFS setup ----------------------------------------------------
RUN git lfs install --system
