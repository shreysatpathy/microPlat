# ML Serving Image with Ray Serve
FROM python:3.11-slim

LABEL org.opencontainers.image.title="ML Platform Serve"
LABEL org.opencontainers.image.description="ML model serving with Ray Serve and FastAPI"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/shreysatpathy/microPlat"

# Create non-root user
RUN groupadd -r serveuser && useradd -r -g serveuser serveuser

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy serving code and models
COPY --chown=serveuser:serveuser src/ ./src/
COPY --chown=serveuser:serveuser models/ ./models/

# Switch to non-root user
USER serveuser

# Expose serving ports
EXPOSE 8000 8265

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Default command
CMD ["python", "-m", "src.serve"]
