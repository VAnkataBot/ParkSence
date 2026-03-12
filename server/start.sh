#!/usr/bin/env bash
# Start the ParkSence API server
#
# Environment variables:
#   LLM_MODEL  — Local mlx-community model ID  (default: mlx-community/Qwen2.5-VL-3B-Instruct-4bit)
#   HF_TOKEN   — HF access token               (enables cloud fallback if local fails)
#   HF_MODEL   — Cloud fallback model ID        (default: Qwen/Qwen2.5-VL-72B-Instruct)
#   SECRET_KEY — JWT secret                     (change in production)
#
# Usage:
#   ./start.sh
#   LLM_MODEL=mlx-community/Qwen2.5-VL-7B-Instruct-4bit HF_TOKEN=hf_xxx ./start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODEL="${LLM_MODEL:-mlx-community/Qwen3-VL-8B-Instruct-4bit}"
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo "  ParkSence API Server"
echo "  ─────────────────────────────────────────"
echo "  Model:   $MODEL"
echo "  Local:   http://localhost:8000"
echo "  Network: http://${LOCAL_IP}:8000"
echo "  Docs:    http://localhost:8000/docs"
echo "  ─────────────────────────────────────────"
echo "  Local model downloads to: server/model/ (~6GB for 3B)"
if [ -n "$HF_TOKEN" ]; then
  echo "  Cloud fallback: ENABLED (${HF_MODEL:-Qwen/Qwen2.5-VL-72B-Instruct})"
else
  echo "  Cloud fallback: disabled  (set HF_TOKEN=hf_xxx to enable)"
fi
echo ""

LLM_MODEL="$MODEL" uvicorn main:app --host 0.0.0.0 --port 8000 --reload
