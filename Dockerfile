# Use a lightweight, stable Linux base
FROM debian:bookworm-slim

# Install necessary runtime dependencies, Git, and SSH client utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    ca-certificates \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install the official OpenCode CLI tool binary
RUN curl -fsSL https://opencode.ai/install | bash

# Create and lock the working directory for your projects
WORKDIR /workspace

# Instruct Git to trust the mounted workspace directory natively 
RUN git config --global --add safe.directory /workspace

# Pre-populate known hosts to prevent interactive verification prompts
RUN mkdir -p -m 0700 /root/.ssh && \
    ssh-keyscan github.com gitlab.com >> /root/.ssh/known_hosts

# Copy our new operational script into the container architecture
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# Register the entrypoint script controller
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# SPIN UP SSH-AGENT, ADD KEY, VERIFY HANDSHAKE, LAUNCH BASH
CMD /bin/bash