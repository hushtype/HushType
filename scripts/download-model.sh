#!/bin/bash
# download-model.sh — Download a model for local development/testing.
#
# Usage: ./scripts/download-model.sh <model-name>
#
# Available models:
#   Whisper (STT):
#     whisper-tiny       Whisper Tiny English (~75 MB)
#     whisper-base       Whisper Base English (~142 MB) [default STT]
#     whisper-small      Whisper Small English (~466 MB)
#     whisper-medium     Whisper Medium English (~1.5 GB)
#     whisper-large      Whisper Large v3 Turbo (~1.5 GB)
#
#   LLM (text processing):
#     qwen2.5-0.5b-q4   Qwen 2.5 0.5B Q4_K_M (~491 MB) [default LLM]
#     qwen2.5-1.5b-q4   Qwen 2.5 1.5B Q4_K_M (~1.1 GB)
#     llama-3.2-1b-q4    Llama 3.2 1B Q4_K_M (~808 MB)
#     gemma-3-1b-q4      Gemma 3 1B Q4_K_M (~806 MB)
#     phi-4-mini-q4      Phi-4 Mini Q4_K_M (~2.5 GB)

set -euo pipefail

MODEL_DIR="$HOME/Library/Application Support/VaulType"
WHISPER_DIR="$MODEL_DIR/whisper-models"
LLM_DIR="$MODEL_DIR/llm-models"

usage() {
    echo "Usage: $0 <model-name>"
    echo ""
    echo "Whisper models:  whisper-tiny, whisper-base, whisper-small, whisper-medium, whisper-large"
    echo "LLM models:      qwen2.5-0.5b-q4, qwen2.5-1.5b-q4, llama-3.2-1b-q4, gemma-3-1b-q4, phi-4-mini-q4"
    exit 1
}

download() {
    local url="$1"
    local dest="$2"
    local name="$3"

    if [ -f "$dest" ]; then
        echo "Already downloaded: $name"
        echo "  Path: $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    echo "Downloading $name..."
    echo "  URL:  $url"
    echo "  Dest: $dest"
    echo ""
    curl -L --progress-bar -o "$dest" "$url"
    echo ""
    echo "Done: $(du -h "$dest" | cut -f1) downloaded"
}

[ $# -lt 1 ] && usage

case "$1" in
    whisper-tiny)
        download \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin" \
            "$WHISPER_DIR/ggml-tiny.en.bin" \
            "Whisper Tiny (English)"
        ;;
    whisper-base)
        download \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" \
            "$WHISPER_DIR/ggml-base.en.bin" \
            "Whisper Base (English)"
        ;;
    whisper-small)
        download \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin" \
            "$WHISPER_DIR/ggml-small.en.bin" \
            "Whisper Small (English)"
        ;;
    whisper-medium)
        download \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin" \
            "$WHISPER_DIR/ggml-medium.en.bin" \
            "Whisper Medium (English)"
        ;;
    whisper-large)
        download \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin" \
            "$WHISPER_DIR/ggml-large-v3-turbo.bin" \
            "Whisper Large v3 Turbo"
        ;;
    qwen2.5-0.5b-q4)
        download \
            "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf" \
            "$LLM_DIR/qwen2.5-0.5b-instruct-q4_k_m.gguf" \
            "Qwen 2.5 0.5B Instruct (Q4_K_M)"
        ;;
    qwen2.5-1.5b-q4)
        download \
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
            "$LLM_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
            "Qwen 2.5 1.5B Instruct (Q4_K_M)"
        ;;
    llama-3.2-1b-q4)
        download \
            "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf" \
            "$LLM_DIR/Llama-3.2-1B-Instruct-Q4_K_M.gguf" \
            "Llama 3.2 1B Instruct (Q4_K_M)"
        ;;
    gemma-3-1b-q4)
        download \
            "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf" \
            "$LLM_DIR/gemma-3-1b-it-Q4_K_M.gguf" \
            "Gemma 3 1B Instruct (Q4_K_M)"
        ;;
    phi-4-mini-q4)
        download \
            "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf" \
            "$LLM_DIR/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf" \
            "Phi-4 Mini Instruct (Q4_K_M)"
        ;;
    *)
        echo "error: Unknown model '$1'"
        echo ""
        usage
        ;;
esac
