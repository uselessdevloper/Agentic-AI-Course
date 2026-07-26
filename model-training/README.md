# Model Training — Data Pipeline

End-to-end pipeline for preparing fine-tuning datasets for the **Enterprise Software Engineering & AI Assistant** LLM.

---

## Full Folder Structure

```
model-training/
│
├── data/
│   ├── raw/                   ← Source documents (clone repos here)
│   │   ├── python/            ← Python official docs
│   │   ├── fastapi/           ← fastapi/fastapi → docs/
│   │   ├── react/             ← reactjs/react.dev → src/content/
│   │   ├── typescript/        ← microsoft/TypeScript-Website → packages/documentation/
│   │   ├── docker/            ← docker/docs → content/
│   │   ├── kubernetes/        ← kubernetes/website → content/en/docs/
│   │   ├── postgresql/        ← postgres/postgres → doc/src/sgml/
│   │   ├── redis/             ← redis/redis-doc → commands/ topics/
│   │   ├── transformers/      ← huggingface/transformers → docs/source/en/
│   │   ├── peft/              ← huggingface/peft → docs/source/
│   │   ├── ollama/            ← ollama/ollama → docs/
│   │   ├── unsloth/           ← unslothai/unsloth → README.md
│   │   ├── langchain/         ← langchain-ai/langchain → docs/docs/
│   │   ├── langgraph/         ← langchain-ai/langgraph → docs/docs/
│   │   ├── llamaindex/        ← run-llama/llama_index → docs/
│   │   ├── qdrant/            ← qdrant/qdrant → docs/
│   │   ├── google-cloud/      ← GoogleCloudPlatform/generative-ai
│   │   └── architecture/      ← YOUR own design docs (TaskPilot, PreservAI, etc.)
│   │
│   ├── markdown/              ← Stage 1 output: converted Markdown files
│   ├── cleaned/               ← Stage 2 output: cleaned & normalized Markdown
│   ├── generated/             ← (Optional) AI-augmented synthetic QA pairs
│   └── datasets/              ← Stage 3 output: final JSONL training data
│       ├── combined.jsonl
│       ├── train.jsonl        (85%)
│       ├── val.jsonl          (10%)
│       └── test.jsonl         ( 5%)
│
├── scripts/
│   ├── clone_repos.sh         ← Clone docs-only from GitHub (sparse checkout)
│   ├── pdf_to_md.py           ← Stage 1: PDF/DOCX/RST/MD → data/markdown/
│   ├── clean_markdown.py      ← Stage 2: Clean noise → data/cleaned/
│   ├── dataset_split.py       ← Stage 3: MD → JSONL + train/val/test split
│   └── jsonl_validator.py     ← Stage 4: Validate dataset quality
│
├── models/                    ← Fine-tuned model checkpoints
├── outputs/                   ← Training logs and eval results
├── notebooks/                 ← Exploration and analysis notebooks
│
├── configs/
│   ├── recipe.yaml            ← Torchtune fine-tuning recipe
│   └── train.yaml             ← Training hyperparameters
│
├── README.md
└── requirements.txt
```

---

## Quick Start

### Step 0 — Install dependencies

```bash
pip install -r requirements.txt
```

### Step 1 — Clone documentation repos (docs-only, sparse checkout)

```bash
cd model-training
./scripts/clone_repos.sh
```

This clones **only the docs subdirectory** from each GitHub repo using `git sparse-checkout`.
No full repo downloads — saves gigabytes of disk space.

### Step 2 — Add your own architecture docs

Drop any `.md`, `.pdf`, or `.docx` files into:
```
data/raw/architecture/
```
Examples: TaskPilot AI design doc, PreservAI system architecture, TrustLens AI notes.

### Step 3 — Run the full pipeline

```bash
# Convert all raw docs (PDF/DOCX/RST/MD) → Markdown
python scripts/pdf_to_md.py

# Clean & normalize all Markdown files
python scripts/clean_markdown.py

# Generate ChatML JSONL pairs + split into train/val/test
python scripts/dataset_split.py --convert --split

# Validate the output datasets
python scripts/jsonl_validator.py data/datasets/
```

---

## Pipeline Diagram

```
data/raw/
  fastapi/  react/  kubernetes/  ...
       │
       ▼  clone_repos.sh  (git sparse-checkout)
       │
       ▼  pdf_to_md.py    (PDF/DOCX/RST/MD → .md)
data/markdown/
       │
       ▼  clean_markdown.py
data/cleaned/
       │
       ▼  dataset_split.py --convert --split
data/datasets/
  combined.jsonl
  train.jsonl  val.jsonl  test.jsonl
       │
       ▼  jsonl_validator.py
  ✅ Validation Report
```

---

## JSONL Format (ChatML)

Each training example uses standard ChatML multi-turn message format:

```json
{
  "messages": [
    {"role": "system",    "content": "You are an expert Enterprise Software Engineering & AI Assistant..."},
    {"role": "user",      "content": "What is Kubernetes HPA? Explain with examples."},
    {"role": "assistant", "content": "HPA (Horizontal Pod Autoscaler) automatically scales pod replicas..."}
  ],
  "metadata": {"source": "kubernetes/hpa.md"}
}
```

---

## Repositories Reference

| Category | GitHub Repo | Docs Path |
|---|---|---|
| FastAPI | `fastapi/fastapi` | `docs/` |
| React | `reactjs/react.dev` | `src/content/` |
| TypeScript | `microsoft/TypeScript-Website` | `packages/documentation/` |
| Docker | `docker/docs` | `content/` |
| Kubernetes | `kubernetes/website` | `content/en/docs/` |
| PostgreSQL | `postgres/postgres` | `doc/src/sgml/` |
| Redis | `redis/redis-doc` | `commands/ topics/` |
| Transformers | `huggingface/transformers` | `docs/source/en/` |
| PEFT | `huggingface/peft` | `docs/source/` |
| Ollama | `ollama/ollama` | `docs/` |
| Unsloth | `unslothai/unsloth` | `README.md` |
| LangChain | `langchain-ai/langchain` | `docs/docs/` |
| LangGraph | `langchain-ai/langgraph` | `docs/docs/` |
| LlamaIndex | `run-llama/llama_index` | `docs/` |
| Qdrant | `qdrant/qdrant` | `docs/` |
| Google Cloud | `GoogleCloudPlatform/generative-ai` | `gemini/ language/` |
| Architecture | Your own content | `data/raw/architecture/` |

---

## Script Reference

| Script | Input | Output |
|---|---|---|
| `clone_repos.sh` | GitHub repos | `data/raw/*/` |
| `pdf_to_md.py` | `data/raw/**/*.{pdf,docx,md,rst}` | `data/markdown/` |
| `clean_markdown.py` | `data/markdown/` | `data/cleaned/` |
| `dataset_split.py --convert --split` | `data/cleaned/` | `data/datasets/` |
| `jsonl_validator.py` | `data/datasets/` | Console report |
