# ML Training Image for Ray Cluster
FROM python:3.11-slim

LABEL org.opencontainers.image.title="ML Platform Trainer"
LABEL org.opencontainers.image.description="ML training container with Ray and MLflow"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/shreysatpathy/microPlat"

# Create non-root user
RUN groupadd -r mluser && useradd -r -g mluser mluser

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy training code
COPY --chown=mluser:mluser src/ ./src/
COPY --chown=mluser:mluser scripts/ ./scripts/

# Switch to non-root user
USER mluser

# Expose Ray ports
EXPOSE 10001 8265

# Default command
CMD ["python", "-m", "src.train"]
