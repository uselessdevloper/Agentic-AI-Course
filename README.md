# 🧠 Agentic AI Course: Engineering Autonomous Agent Systems

An end-to-end repository for building, fine-tuning, securing, and orchestrating production-grade autonomous AI agents, multi-agent systems, and domain-adapted LLMs.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Repository Architecture](#-repository-architecture)
- [Core Modules](#-core-modules)
  - [1. Skillspector: Agent Security & Skill Gate](#1-skillspector-agent-security--skill-gate)
  - [2. Model Training & Data Pipeline](#2-model-training--data-pipeline)
  - [3. Prompt Engineering & Research Agents](#3-prompt-engineering--research-agents)
  - [4. Agentic Ecosystem (OpenClaw + Multica + AnythingLLM MCP)](#4-agentic-ecosystem-openclaw--multica--anythingllm-mcp)
- [Datasets](#-datasets)
- [Installation & Quickstart](#-installation--quickstart)
- [Contributing & Best Practices](#-contributing--best-practices)

---

## 🌟 Overview

This repository provides hands-on code, pipelines, and frameworks covering the full lifecycle of Agentic AI:
* **Model Training & Adaptation**: High-throughput pipelines for converting unstructured documentation (PDF, DOCX, RST, Markdown) into structured instruction datasets, paired with LoRA/QLoRA fine-tuning recipes.
* **Skill Security Inspection (Skillspector)**: Automated AST, regex, prompt injection, and credential leak scanning for LLM agent skills.
* **Gate Operations**: Automated admission control pipelines for vetting agent skills before deployment.
* **Multi-Agent Runtime & Protocol (MCP)**: Integrating OpenClaw, AnythingLLM RAG, and Multica Desktop via the Model Context Protocol (FastMCP).

---

## 📁 Repository Architecture

```text
agentic-ai-course/
├── dataset/                                # Labeled skill datasets for testing & benchmarking
│   ├── safe/                               # Verified safe skill definitions
│   └── malicious/                          # Synthetic malicious skills for security testing
├── model-training/                         # End-to-end LLM fine-tuning & data curation
│   ├── configs/                            # Training recipes (YAML) and run configs
│   ├── data/datasets/                      # Train, validation, and test JSONL splits
│   └── scripts/                            # Pipeline scripts (PDF-to-MD, cleaning, splitting)
├── skillspector/                           # Static security & vulnerability scanner for agent skills
│   ├── pyproject.toml                      # Skillspector package configuration
│   └── skillspector/
│       ├── main.py                         # CLI entrypoint
│       ├── parser.py                       # SKILL.md and metadata parser
│       ├── risk_engine.py                  # Multi-vector risk scoring engine
│       ├── scanners/                       # AST, prompt injection, secret, and code scanners
│       └── reporters/                      # Rich terminal and JSON formatters
├── skillspector-gate-ops/                  # CI/CD & Gate operations automation scripts
├── .github/agents/                         # Custom GitHub agent definitions (e.g., research agent)
├── UBUNTU_VM_SETUP_GUIDE.md                # GPU VM cloud provisioning guide
└── README.md                               # Project documentation
```

---

## 🚀 Core Modules

### 1. Skillspector: Agent Security & Skill Gate
**Skillspector** evaluates custom LLM skills (`SKILL.md`) for common vulnerabilities before they are loaded into runtime agents:
* **Prompt Injection Detection**: Identifies instruction overriding, delimiter breaking, and jailbreak phrases.
* **Hardcoded Secret Scanner**: Catches leaked API keys, tokens, and SSH credentials.
* **Dangerous Command & Code Execution**: Inspects Python/Bash scripts for unsanitized `rm -rf`, arbitrary subprocesses, and reverse shells.
* **Dependency & URL Analysis**: Flags untrusted package installations and suspicious exfiltration endpoints.

```bash
# Run Skillspector against a skill directory
skillspector scan dataset/safe/hello-world/
```

---

### 2. Model Training & Data Pipeline
A modular data preparation and instruction-tuning framework:
* **`pdf_to_md.py`**: Extracts text from raw technical documentation.
* **`clean_dataset.py`**: Normalizes schemas, strips formatting noise, and removes low-quality pairs.
* **`recipe.yaml`**: LLaMA-Factory / Torchtune fine-tuning recipe specifying LoRA hyperparameters, batch size, learning rates, and target layers.

---

### 3. Prompt Engineering & Research Agents
* Structured labs exploring zero-shot, few-shot, Chain-of-Thought (CoT), ReAct prompting, and agent personas.
* Declarative agent specifications located in `.github/agents/`.

---

### 4. Agentic Ecosystem (OpenClaw + Multica + AnythingLLM MCP)
Connects disparate knowledge bases, runtimes, and user interfaces using standard protocols:

```
AnythingLLM (RAG Engine)
       │
       ▼
AnythingLLM MCP Server (FastMCP)
       │
       ▼
OpenClaw Runtime (Agent Core)
       │
       ▼
Multica Desktop / Discord Gateway
```

---

## 📊 Datasets

The repository includes curated datasets for model training and security validation:
* `model-training/data/datasets/`: Instruction-response datasets (`train_clean.jsonl`, `val_clean.jsonl`, `test_clean.jsonl`).
* `dataset/`: Standardized skill schemas labeled with security metadata (`security_label.json`).

---

## ⚙️ Installation & Quickstart

### Prerequisites
* Python 3.10+
* Git
* Node.js (optional, for web UI and MCP server integrations)

### 1. Clone & Set Up Environment
```bash
git clone https://github.com/uselessdevloper/Agentic-AI-Course.git
cd Agentic-AI-Course

python3 -m venv .venv
source .venv/bin/activate
pip install -e ./skillspector
```

### 2. Run Skillspector
```bash
skillspector scan dataset/safe/hello-world/
```

---

## 📝 License

Distributed under the MIT License. See `LICENSE` for more information.
