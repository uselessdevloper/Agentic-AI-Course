#!/usr/bin/env bash
# =============================================================================
# clone_repos.sh
# Clones ONLY the documentation subdirectories from each repository using
# git sparse-checkout (no full repo download — saves gigabytes of disk space).
#
# Usage:
#   cd model-training
#   chmod +x scripts/clone_repos.sh
#   ./scripts/clone_repos.sh
#
# Requirements: git >= 2.25 (for sparse-checkout support)
# =============================================================================

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_DIR="$(cd "$SCRIPT_DIR/../data/raw" && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }
info() { echo -e "${BLUE}→  $*${NC}"; }

# ── Helper: sparse clone ───────────────────────────────────────────────────────
# sparse_clone <repo_url> <target_dir> <sparse_path1> [sparse_path2 ...]
sparse_clone() {
    local repo_url="$1"
    local target_dir="$2"
    shift 2
    local sparse_paths=("$@")

    if [[ -d "$target_dir/.git" ]]; then
        warn "Already cloned: $(basename "$target_dir") — skipping"
        return 0
    fi

    info "Cloning $(basename "$target_dir") from $repo_url"
    info "  Sparse paths: ${sparse_paths[*]}"

    git clone \
        --depth 1 \
        --filter=blob:none \
        --sparse \
        --single-branch \
        "$repo_url" \
        "$target_dir" 2>&1 | grep -v "^Cloning\|^remote:\|^Receiving\|^Resolving\|^Updating" || true

    pushd "$target_dir" > /dev/null

    git sparse-checkout set --no-cone "${sparse_paths[@]}"
    git checkout 2>&1 | tail -1 || true

    popd > /dev/null
    ok "Done: $(basename "$target_dir")"
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Enterprise AI Assistant — Documentation Cloner"
echo "  Target: $RAW_DIR"
echo "============================================================"
echo ""

# 1. FastAPI
sparse_clone \
    "https://github.com/fastapi/fastapi.git" \
    "$RAW_DIR/fastapi" \
    "docs"

# 2. React (react.dev — the modern React documentation site)
sparse_clone \
    "https://github.com/reactjs/react.dev.git" \
    "$RAW_DIR/react" \
    "src/content"

# 3. TypeScript (TypeScript-Website monorepo)
sparse_clone \
    "https://github.com/microsoft/TypeScript-Website.git" \
    "$RAW_DIR/typescript" \
    "packages/documentation"

# 4. Docker Docs
sparse_clone \
    "https://github.com/docker/docs.git" \
    "$RAW_DIR/docker" \
    "content"

# 5. Kubernetes Website
sparse_clone \
    "https://github.com/kubernetes/website.git" \
    "$RAW_DIR/kubernetes" \
    "content/en/docs"

# 6. PostgreSQL (only doc source — sgml + rst files)
sparse_clone \
    "https://github.com/postgres/postgres.git" \
    "$RAW_DIR/postgresql" \
    "doc/src/sgml" \
    "doc/src/tutorial"

# 7. Redis Documentation
sparse_clone \
    "https://github.com/redis/redis-doc.git" \
    "$RAW_DIR/redis" \
    "commands" \
    "topics"

# 8. Hugging Face Transformers
sparse_clone \
    "https://github.com/huggingface/transformers.git" \
    "$RAW_DIR/transformers" \
    "docs/source/en"

# 9. PEFT (Parameter-Efficient Fine-Tuning)
sparse_clone \
    "https://github.com/huggingface/peft.git" \
    "$RAW_DIR/peft" \
    "docs/source"

# 10. Ollama
sparse_clone \
    "https://github.com/ollama/ollama.git" \
    "$RAW_DIR/ollama" \
    "docs"

# 11. Unsloth (wiki-style docs live in main repo)
sparse_clone \
    "https://github.com/unslothai/unsloth.git" \
    "$RAW_DIR/unsloth" \
    "README.md"

# 12. LangChain
sparse_clone \
    "https://github.com/langchain-ai/langchain.git" \
    "$RAW_DIR/langchain" \
    "docs/docs"

# 13. LangGraph
sparse_clone \
    "https://github.com/langchain-ai/langgraph.git" \
    "$RAW_DIR/langgraph" \
    "docs/docs"

# 14. LlamaIndex
sparse_clone \
    "https://github.com/run-llama/llama_index.git" \
    "$RAW_DIR/llamaindex" \
    "docs"

# 15. Qdrant (landing page / docs repo)
sparse_clone \
    "https://github.com/qdrant/qdrant.git" \
    "$RAW_DIR/qdrant" \
    "docs"

# 16. Google Cloud — Generative AI samples & guides
sparse_clone \
    "https://github.com/GoogleCloudPlatform/generative-ai.git" \
    "$RAW_DIR/google-cloud" \
    "gemini" \
    "language" \
    "vision" \
    "CHANGELOG.md" \
    "README.md"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Clone Summary"
echo "============================================================"

TOTAL=0
FOUND=0
for dir in "$RAW_DIR"/*/; do
    name=$(basename "$dir")
    TOTAL=$((TOTAL + 1))
    if [[ -d "$dir/.git" ]]; then
        file_count=$(find "$dir" -type f \( -name "*.md" -o -name "*.mdx" -o -name "*.rst" -o -name "*.sgml" \) 2>/dev/null | wc -l | tr -d ' ')
        ok "$name: $file_count doc files"
        FOUND=$((FOUND + 1))
    else
        warn "$name: not yet cloned"
    fi
done

echo ""
echo "  Cloned: $FOUND / $TOTAL repositories"
echo ""
echo "  Next steps:"
echo "    python scripts/pdf_to_md.py      # Convert any PDFs"
echo "    python scripts/clean_markdown.py # Clean all markdown"
echo "    python scripts/dataset_split.py --convert --split"
echo "============================================================"
