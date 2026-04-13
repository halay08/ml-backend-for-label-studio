# ML Backend Base Image (Label Studio–compatible)

A reusable Docker base image for running **[Label Studio ML](https://github.com/HumanSignal/label-studio-ml-backend)** backends with common computer-vision and inference dependencies preinstalled.

This image provides:

- Python runtime (`python:3.12-slim`)
- OS libraries needed for typical CV pipelines
- Pinned Python dependencies (Label Studio ML, Gunicorn, Ultralytics stack, CPU PyTorch, and related libs)
- A **Gunicorn** entrypoint with sensible defaults, overridable via environment variables
- Optional **baked-in Ultralytics SAM weights** (default `sam2_l.pt` from [ultralytics/assets](https://github.com/ultralytics/assets/releases)) via build-args so the first inference does not download

**It does not ship application code.** Build your own image `FROM` this one, copy your backend package (e.g. `_wsgi.py`, model classes), and set `CMD` to your WSGI target. Set `SAM_MODEL_NAME` at runtime to match the weight filename you baked (or override with a mounted file in `/app`).

---

## What it is for

Use as a **shared runtime layer** when you want:

- A Label Studio ML backend served with Gunicorn
- YOLO/SAM-style inference without rebuilding the same dependency stack in every project

Consumer projects only add their code and configuration on top.

---

## Build

From this directory (where the `Dockerfile` lives):

```bash
docker build --platform=linux/amd64 -t heartexlab/ml-backend:latest .
```

**SAM weights (build-time):** defaults download `sam2_l.pt` from `https://github.com/ultralytics/assets/releases/download/v8.4.0/`. Override or skip:

| Build arg | Default | Meaning |
| --- | --- | --- |
| `SAM_PRELOAD_PT` | `sam2_l.pt` | Weight filename (`sam2_t.pt`, `sam2_b.pt`, `sam2_l.pt`, …). Empty string skips download. |
| `SAM_ASSETS_RELEASE` | `v8.4.0` | Release tag on `ultralytics/assets`. |

```bash
docker build --platform=linux/amd64 \
  --build-arg SAM_PRELOAD_PT=sam2_t.pt \
  --build-arg SAM_ASSETS_RELEASE=v8.4.0 \
  -t heartexlab/ml-backend:latest .
```

The image sets `ENV SAM_MODEL_NAME` to the same value as `SAM_PRELOAD_PT` when non-empty; override at `docker run` / Compose if you mount a different checkpoint into `/app`.

Include optional test dependencies at build time:

```bash
docker build --build-arg TEST_ENV=true --platform=linux/amd64 -t heartexlab/ml-backend:latest .
```

---

## Runtime defaults

The image `ENTRYPOINT` runs Gunicorn with:

```bash
gunicorn --bind 0.0.0.0:${PORT} --workers ${WORKERS} --threads ${THREADS} --timeout ${TIMEOUT}
```

Default environment:

| Variable   | Default |
| ---------- | ------- |
| `PORT`     | `9090`  |
| `WORKERS`  | `1`     |
| `THREADS`  | `4`     |
| `TIMEOUT`  | `180`   |

Override any of these at `docker run` time.

---

## Using this image in your app image

Example pattern (replace paths and module names with yours):

```dockerfile
FROM heartexlab/ml-backend:latest
WORKDIR /app
COPY your_shared_lib/ ./your_shared_lib/
COPY your_ml_backend/ ./your_ml_backend/
CMD ["your_ml_backend._wsgi:app"]
```

Run:

```bash
docker run --rm -p 9090:9090 \
  -e PORT=9090 \
  -e WORKERS=1 \
  -e THREADS=4 \
  -e TIMEOUT=180 \
  your-registry/your-ml-backend:latest
```

---

## Models and configuration

**SAM vs detector weights (Sphere / Label Studio apps):** SAM checkpoints baked or set via `SAM_MODEL_NAME` are **Ultralytics generic segmentation** weights — they are **not** registered in your app’s `model_versions` table. The **YOLO detector** (`best.pt` / OpenVINO) used for bounding boxes is resolved separately (typically DB `is_latest` + S3). Do not assume every `.pt` in the stack comes from the same source.

By default this image **downloads one SAM 2 checkpoint into `/app`** at build time (see build-args above). Your app can still use other weights by setting `SAM_MODEL_NAME` and providing the file under `/app` or Ultralytics’ cache.

If you skip the bake (`--build-arg SAM_PRELOAD_PT=`), **SAM 2** weights (`sam2_t.pt`, …) can **auto-download** on first inference. See [Ultralytics SAM 2](https://docs.ultralytics.com/models/sam-2/).

For **SAM 3**, weights are named `sam3.pt` (~3.4GB) and are **not** auto-downloaded: request access on the model’s Hugging Face page, download the file, and place it under the process working directory (e.g. `/app`) or `~/.ultralytics` in the container. See [Ultralytics SAM 3](https://docs.ultralytics.com/models/sam-3/).

---

## Notes

- Dependencies are **pinned** for reproducible builds.
- **CPU** PyTorch wheels are used to avoid pulling CUDA-only dependency chains into a slim image.
- Targets **Linux amd64** (`linux/amd64`) by default.
