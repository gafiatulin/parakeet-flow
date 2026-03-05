#!/usr/bin/env bash
# Push sherpa-onnx ONNX models and test audio to the device for instrumentation tests.
#
# Usage: ./scripts/push_test_models.sh
#
# Prerequisites — download models first:
#   gh release download asr-models -R k2-fsa/sherpa-onnx -p sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2
#   tar xjf sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2 -C scripts/models/parakeet-tdt-sherpa/
#
# Expected layout:
#   scripts/models/parakeet-tdt-sherpa/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/
#     encoder.int8.onnx, decoder.int8.onnx, joiner.int8.onnx, tokens.txt

set -euo pipefail

# Run from android/ directory
cd "$(dirname "$0")/.."

ADB=~/Library/Android/sdk/platform-tools/adb
MODEL_DIR="scripts/models/parakeet-tdt-sherpa/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
TEST_DIR="/data/local/tmp/parakeet-test"

REQUIRED_FILES=(
    "encoder.int8.onnx"
    "decoder.int8.onnx"
    "joiner.int8.onnx"
    "tokens.txt"
)

echo "=== Pushing sherpa-onnx models to device ==="

# Check model files exist
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$MODEL_DIR/$f" ]]; then
        echo "ERROR: Missing $MODEL_DIR/$f"
        exit 1
    fi
done

# Use bundled test wav or existing device test.wav
TEST_WAV="$MODEL_DIR/test_wavs/0.wav"

# Create target directory
$ADB shell mkdir -p "$TEST_DIR"

# Push model files
for f in "${REQUIRED_FILES[@]}"; do
    echo "Pushing $f..."
    $ADB push "$MODEL_DIR/$f" "$TEST_DIR/$f"
done

# Push test audio (use bundled wav, or reuse existing on device)
if [[ -f "$TEST_WAV" ]]; then
    echo "Pushing test.wav..."
    $ADB push "$TEST_WAV" "$TEST_DIR/test.wav"
else
    echo "No local test.wav found, checking device..."
    $ADB shell "test -f $TEST_DIR/test.wav" || { echo "ERROR: No test.wav on device either"; exit 1; }
    echo "Using existing test.wav on device"
fi

echo "=== Done. Files on device: ==="
$ADB shell ls -la "$TEST_DIR/"
