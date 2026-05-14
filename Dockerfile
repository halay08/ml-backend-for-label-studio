# syntax=docker/dockerfile:1
# Base image: OS deps, Python packages, runtime defaults, optional Ultralytics SAM weights baked in.
# Build: docker build -f ml_backend/Dockerfile -t heartexlab/ml-backend:latest .
#   Override weights: --build-arg SAM_PRELOAD_PT=sam2_t.pt --build-arg SAM_ASSETS_RELEASE=v8.4.0
#   Skip download: --build-arg SAM_PRELOAD_PT=
# Runtime: sphere-ai/ml_backend/Dockerfile FROM this image + COPY shared + ml_backend
FROM python:3.12-slim
ARG TEST_ENV=false
# Ultralytics release assets: https://github.com/ultralytics/assets/releases
ARG SAM_ASSETS_RELEASE=v8.4.0
# Filename only, e.g. sam2_t.pt | sam2.1_s.pt | sam2_l.pt (baked to /app; sets ENV SAM_MODEL_NAME below)
ARG SAM_PRELOAD_PT=sam2_l.pt

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_CACHE_DIR=/.cache \
    PORT=9090 \
    WORKERS=1 \
    THREADS=4 \
    TIMEOUT=180

RUN --mount=type=cache,target="/var/cache/apt",sharing=locked \
    --mount=type=cache,target="/var/lib/apt/lists",sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libgl1 \
      libglib2.0-0; \
    apt-get autoremove -y

WORKDIR /app
EXPOSE 9090

COPY requirements-base.txt requirements.txt requirements-test.txt /tmp/
RUN --mount=type=cache,target=${PIP_CACHE_DIR},sharing=locked \
    set -eux; \
    req_files="-r /tmp/requirements-base.txt -r /tmp/requirements.txt"; \
    if [ "$TEST_ENV" = "true" ]; then \
      req_files="$req_files -r /tmp/requirements-test.txt"; \
    fi; \
    pip install --no-cache-dir $req_files; \
    rm -f /tmp/requirements-base.txt /tmp/requirements.txt /tmp/requirements-test.txt

# Bake SAM weights into /app (WORKDIR) so first inference does not download.
RUN set -eux; \
    if [ -n "${SAM_PRELOAD_PT}" ]; then \
      url="https://github.com/ultralytics/assets/releases/download/${SAM_ASSETS_RELEASE}/${SAM_PRELOAD_PT}"; \
      echo "Downloading ${url}"; \
      curl -fSL --retry 3 --retry-delay 2 -o "/app/${SAM_PRELOAD_PT}" "${url}"; \
    else \
      echo "SAM_PRELOAD_PT empty — skipping weight download (runtime will fetch or mount)."; \
    fi

# Runtime default unless overridden by container env (e.g. SAM_MODEL_NAME in .env).
ENV SAM_MODEL_NAME=${SAM_PRELOAD_PT}

ENTRYPOINT ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers ${WORKERS} --threads ${THREADS} --timeout ${TIMEOUT} \"$@\"", "--"]
