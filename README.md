# ScratchAgents (Raku)

Raku port of the companion codebase for *Build an AI Agent from Scratch*.

## Overview

`ScratchAgents` implements a modular AI agent framework in Raku:

- **Core Types & Context**: `ScratchAgents::Types`, `ScratchAgents::Context`
- **LLM Client**: `ScratchAgents::Llm` (`Cro::HTTP::Client`, `JSON::Fast`, OpenAI-compatible Chat Completions + structured output)
- **Agent Loop (ReAct)**: `ScratchAgents::Agent` (tool calling, structured `final_answer`, human-in-the-loop confirmations, callbacks, code sandbox, skills, multi-agent transfer)
- **Tools**: `Base`, `Helpers`, `Calculator`, `Search` (Tavily), `FileTools` (`Spreadsheet::XLSX`, `pdftotext`/`pdftoppm`), `CodeExecution` (E2B REST), `Mcp` (stdio JSON-RPC via `Proc::Async`), `MemoryTool`, `AgentTool`
- **Memory & Context Optimization**: `Memory::Session`, `Memory::LongTerm` (`DBIish` SQLite + pure-Raku cosine similarity), `Memory::ContextOptimizer` (`Tokenizers` / tiktoken bindings + sliding window, compaction, summarization)
- **RAG, Callbacks, Planning & Skills**: `Rag`, `Callbacks`, `Planning`, `Skills` (`YAMLish`)
- **Multi-Agent & A2A**: `Transfer`, `Remote`, `A2AServer`, `Workflows::{Sequential,Parallel,Loop}`
- **Evaluation**: `Eval::Gaia`, `Eval::Prompts`

## Dependencies

Install module dependencies with `zef`:

```sh
zef install --deps-only .
```

Key ecosystem modules used from `raku.land`:
- `Cro::HTTP` — async HTTP client for OpenAI, Tavily, E2B, and A2A endpoints
- `JSON::Fast` — fast JSON parsing and serialization
- `Env::Dotenv` — `.env` configuration loading
- `YAMLish` — YAML frontmatter parsing for `SKILL.md`
- `UUID` — UUID v4 generation for events and execution IDs
- `MIME::Base64` — base64 encoding for image/audio/PDF inputs
- `DBIish` — SQLite storage replacing ChromaDB for long-term task memories
- `Tokenizers` — Rust bindings (`tokenizers` / `tiktoken`) for token counting
- `Spreadsheet::XLSX` — optional runtime dependency for reading `.xlsx` spreadsheets

## Running Tests

```sh
prove6 -Ilib t/
# or
for f in t/*.rakutest; do raku -Ilib "$f"; done
```

## Running Examples

```sh
# Offline / self-contained examples (no API key required)
raku examples/ch04-structured-output.raku
raku examples/ch05-mcp-tools.raku
raku examples/ch05-rag-callbacks.raku
raku examples/ch06-long-term-memory.raku
raku examples/ch06-memory-hitl.raku
raku examples/ch07-planning-files.raku
raku examples/ch08-skills-sandbox.raku
raku examples/ch09-multi-agent.raku
raku examples/ch09-agent-transfer-and-tool.raku
raku examples/ch09-a2a-server-client.raku
raku examples/ch10-evaluation.raku

# Live LLM examples (uses .env / OPENAI_API_KEY)
raku examples/ch02-llm-basics.raku
raku examples/ch03-04-react-agent.raku
raku examples/ch05-mcp-tools.raku --live
raku examples/ch04-structured-output.raku --live
```
