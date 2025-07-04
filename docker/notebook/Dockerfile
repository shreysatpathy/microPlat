# Jupyter Notebook Image for ML Platform
FROM jupyter/scipy-notebook:python-3.11

LABEL org.opencontainers.image.title="ML Platform Notebook"
LABEL org.opencontainers.image.description="Jupyter notebook with ML libraries and Ray client"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/shreysatpathy/microPlat"

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

USER $NB_UID

# Install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Install Ray and ML libraries
RUN pip install --no-cache-dir \
    ray[default]==2.47.0 \
    mlflow \
    scikit-learn \
    xgboost \
    lightgbm \
    optuna \
    plotly \
    seaborn

# Copy notebooks and examples
COPY --chown=$NB_UID:$NB_GID notebooks/ /home/$NB_USER/work/

# Set working directory
WORKDIR /home/$NB_USER/work

# Expose Jupyter port
EXPOSE 8888

# Default command (inherited from base image)
CMD ["start-notebook.sh"]
