#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAYER_DIR="$PROJECT_ROOT/cdk/lambda/layer"

echo "Building Lambda layer..."

# Clean up existing python directory
rm -rf "$LAYER_DIR/python"
mkdir -p "$LAYER_DIR/python"

# Check if Docker is available
if command -v docker &> /dev/null; then
    echo "Using Docker to build layer (recommended for Linux compatibility)..."
    docker run --rm \
        -v "$LAYER_DIR:/var/task" \
        public.ecr.aws/sam/build-python3.12:latest \
        pip install -r /var/task/requirements.txt -t /var/task/python --no-cache-dir
else
    echo "Docker not found. Using local pip (may have compatibility issues on macOS)..."
    pip install -r "$LAYER_DIR/requirements.txt" -t "$LAYER_DIR/python" --no-cache-dir
fi

echo "Lambda layer built successfully!"
echo "Layer directory: $LAYER_DIR/python"
ls -la "$LAYER_DIR/python"
