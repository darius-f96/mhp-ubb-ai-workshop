#!/usr/bin/env python3
"""
Local RAG in one file, with no dependencies beyond the Python standard library.

Retrieval-Augmented Generation, spelled out:

    documents -> chunks -> embeddings -> stored vectors
    question  -> embedding -> cosine similarity -> top-k chunks
    top-k chunks + question -> chat model -> answer

Every piece runs on your laptop against the stack you built in this workshop.
No LangChain, no vector database, no frameworks -- the point is that RAG is
about 150 lines of ordinary code, and once you have written it you will never
be mystified by a library doing it for you.

Usage:
    python3 rag.py index                      # build the vector index
    python3 rag.py ask "what is llama-swap?"  # retrieve and answer
    python3 rag.py search "context window"    # retrieval only, no LLM

The `search` subcommand is the one to use while debugging: it shows you what
retrieval found WITHOUT the chat model involved, so you can tell a retrieval
problem from a generation problem. That distinction is most of RAG tuning.

Point it at any OpenAI-compatible endpoint:
    --base-url http://127.0.0.1:8090/v1     # llama-swap directly
    --base-url http://127.0.0.1:4000/v1     # through LiteLLM (recommended)
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# ── Defaults ────────────────────────────────────────────────────────────────
# These match configs/llama-swap/config.yaml. Override on the command line.
DEFAULT_BASE_URL = os.environ.get("RAG_BASE_URL", "http://127.0.0.1:4000/v1")
DEFAULT_EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "local-embed")
DEFAULT_CHAT_MODEL = os.environ.get("RAG_CHAT_MODEL", "local-chat")

# Index the workshop's own docs -- a corpus the students have actually read,
# which makes a bad retrieval result obvious to them.
# This file lives at <repo>/exercises/rag/rag.py, so the repo root is three
# levels up. Verified, not guessed -- getting this wrong silently indexes
# nothing.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_DOCS = REPO_ROOT / "docs"
INDEX_PATH = Path(__file__).resolve().parent / "index.json"

CHUNK_CHARS = 1200   # ~300 tokens. Small enough to stay relevant, big enough
                     # to keep a paragraph intact.
CHUNK_OVERLAP = 200  # overlap so a sentence split across a boundary is still
                     # findable in one of the two chunks.


# ── Chunking ────────────────────────────────────────────────────────────────
def chunk_text(text: str, size: int = CHUNK_CHARS, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split on paragraph boundaries, then pack paragraphs into chunks.

    Splitting on blank lines rather than a raw character count keeps headings
    with the prose they introduce. A chunk that starts mid-sentence retrieves
    fine but reads as noise once it is pasted into a prompt.
    """
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    current = ""

    for para in paragraphs:
        # A single paragraph larger than the target gets hard-split. Long code
        # blocks and tables do this, and dropping them would lose real content.
        if len(para) > size:
            if current:
                chunks.append(current)
                current = ""
            step = size - overlap
            for i in range(0, len(para), step):
                chunks.append(para[i : i + size])
            continue

        if len(current) + len(para) + 2 <= size:
            current = f"{current}\n\n{para}" if current else para
        else:
            if current:
                chunks.append(current)
            # Carry the tail of the previous chunk forward for overlap.
            current = (current[-overlap:] + "\n\n" + para) if current and overlap else para

    if current:
        chunks.append(current)
    return chunks


# ── Vectors, without numpy ──────────────────────────────────────────────────
def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        raise ValueError(f"dimension mismatch: {len(a)} vs {len(b)}")
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (na * nb)


# ── HTTP ────────────────────────────────────────────────────────────────────
def post_json(url: str, payload: dict, api_key: str, timeout: int = 180) -> dict:
    """POST JSON to an OpenAI-compatible endpoint. No requests, no SDK."""
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            # A key is always sent: LiteLLM requires one, and a keyless
            # llama.cpp simply ignores it. "dummy" is the convention.
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        raise SystemExit(f"HTTP {e.code} from {url}\n{detail}") from None
    except urllib.error.URLError as e:
        raise SystemExit(
            f"Cannot reach {url}: {e.reason}\n"
            "Is the server running?  ./scripts/healthcheck.sh"
        ) from None


def embed(texts: list[str], base_url: str, model: str, api_key: str) -> list[list[float]]:
    """Embed a batch of texts. Batching matters: one request, not N."""
    data = post_json(
        f"{base_url}/embeddings",
        {"model": model, "input": texts},
        api_key,
    )
    items = data.get("data") or []
    # The API does not guarantee response order, so sort by `index`.
    items = sorted(items, key=lambda d: d.get("index", 0))
    vectors = [d["embedding"] for d in items]
    if len(vectors) != len(texts):
        raise SystemExit(f"expected {len(texts)} embeddings, got {len(vectors)}")
    return vectors


# ── Subcommands ─────────────────────────────────────────────────────────────
def cmd_index(args: argparse.Namespace) -> int:
    docs_dir = Path(args.docs)
    if not docs_dir.is_dir():
        raise SystemExit(f"no such directory: {docs_dir}")

    files = sorted(p for p in docs_dir.rglob("*.md"))
    if not files:
        raise SystemExit(f"no .md files under {docs_dir}")

    records: list[dict] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for i, chunk in enumerate(chunk_text(text)):
            records.append(
                {
                    "source": str(path.relative_to(docs_dir.parent)),
                    "chunk": i,
                    "text": chunk,
                }
            )

    print(f"chunked {len(files)} files into {len(records)} chunks")
    if not records:
        return 1

    # Embed in batches -- a single request with 400 chunks will usually be
    # rejected or time out.
    batch = args.batch_size
    for start in range(0, len(records), batch):
        group = records[start : start + batch]
        vectors = embed([r["text"] for r in group], args.base_url, args.embed_model, args.api_key)
        for rec, vec in zip(group, vectors):
            rec["embedding"] = vec
        print(f"  embedded {min(start + batch, len(records))}/{len(records)}", end="\r")

    dims = len(records[0]["embedding"])
    INDEX_PATH.write_text(json.dumps({"model": args.embed_model, "dims": dims, "records": records}))
    size_mb = INDEX_PATH.stat().st_size / 1e6
    print(f"\nwrote {INDEX_PATH}  ({len(records)} chunks, {dims} dims, {size_mb:.1f} MB)")
    return 0


def load_index() -> tuple[dict, list[dict]]:
    if not INDEX_PATH.exists():
        raise SystemExit(f"no index at {INDEX_PATH} -- run: python3 rag.py index")
    data = json.loads(INDEX_PATH.read_text())
    return data, data["records"]


def retrieve(query: str, args: argparse.Namespace) -> list[tuple[float, dict]]:
    _, records = load_index()
    qvec = embed([query], args.base_url, args.embed_model, args.api_key)[0]
    scored = [(cosine_similarity(qvec, r["embedding"]), r) for r in records]
    scored.sort(key=lambda t: t[0], reverse=True)
    return scored[: args.top_k]


def cmd_search(args: argparse.Namespace) -> int:
    """Retrieval only. Use this to debug -- it removes the LLM from the picture."""
    hits = retrieve(args.query, args)
    if not hits:
        print("no results")
        return 1
    print(f"query: {args.query}\n")
    for rank, (score, rec) in enumerate(hits, 1):
        preview = " ".join(rec["text"].split())[:180]
        print(f"{rank}. score={score:.4f}  {rec['source']} (chunk {rec['chunk']})")
        print(f"   {preview}…\n")
    return 0


def cmd_ask(args: argparse.Namespace) -> int:
    hits = retrieve(args.query, args)
    if not hits:
        raise SystemExit("retrieval found nothing -- is the index built?")

    # Build the context block. Numbering the sources lets the model cite them,
    # which makes a hallucinated answer much easier to spot.
    context = "\n\n".join(
        f"[{i}] (from {rec['source']})\n{rec['text']}" for i, (_, rec) in enumerate(hits, 1)
    )

    system = (
        "Answer using ONLY the numbered context below. Cite the source numbers "
        "you used, like [1] or [2]. If the context does not contain the answer, "
        "say so plainly -- do not fill the gap from memory."
    )
    user = f"Context:\n{context}\n\nQuestion: {args.query}"

    if args.verbose:
        print(f"retrieved {len(hits)} chunks, prompt is ~{len(user) // 4} tokens\n", file=sys.stderr)

    resp = post_json(
        f"{args.base_url}/chat/completions",
        {
            "model": args.chat_model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            # Small models spend their whole budget on reasoning and return an
            # EMPTY content field if this is too low. It looks like a crash and
            # is not. See docs/troubleshooting.md#thinking-models
            "max_tokens": args.max_tokens,
            "temperature": 0.2,
        },
        args.api_key,
    )

    msg = (resp.get("choices") or [{}])[0].get("message") or {}
    answer = (msg.get("content") or "").strip()
    reasoning = (msg.get("reasoning_content") or "").strip()

    if not answer:
        print("The model returned an empty answer.", file=sys.stderr)
        if reasoning:
            print(f"It produced {len(reasoning)} chars of reasoning instead -- raise "
                  "--max-tokens, or disable thinking with --reasoning-budget 0 on the "
                  "server. See docs/troubleshooting.md#thinking-models", file=sys.stderr)
        else:
            print("Check the server log. A cold llama-swap load can exceed the client "
                  "timeout.", file=sys.stderr)
        return 1

    print(answer)
    print("\n── sources ──")
    for i, (score, rec) in enumerate(hits, 1):
        print(f"  [{i}] {rec['source']} chunk {rec['chunk']}  (score {score:.4f})")
    return 0


# ── CLI ─────────────────────────────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Dependency-free local RAG over the workshop docs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:")[1] if "Usage:" in __doc__ else None,
    )
    p.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"OpenAI-compatible base URL (default: {DEFAULT_BASE_URL})")
    p.add_argument("--embed-model", default=DEFAULT_EMBED_MODEL, help=f"embedding model id (default: {DEFAULT_EMBED_MODEL})")
    p.add_argument("--chat-model", default=DEFAULT_CHAT_MODEL, help=f"chat model id (default: {DEFAULT_CHAT_MODEL})")
    p.add_argument("--api-key", default=os.environ.get("LITELLM_API_KEY", "dummy"),
                   help="API key; defaults to $LITELLM_API_KEY, then 'dummy'")

    sub = p.add_subparsers(dest="command", required=True)

    pi = sub.add_parser("index", help="chunk and embed the docs into index.json")
    pi.add_argument("--docs", default=str(DEFAULT_DOCS), help=f"directory of .md files (default: {DEFAULT_DOCS})")
    pi.add_argument("--batch-size", type=int, default=32, help="texts per embeddings request (default: 32)")
    pi.set_defaults(func=cmd_index)

    ps = sub.add_parser("search", help="retrieve only -- no LLM, for debugging")
    ps.add_argument("query")
    ps.add_argument("--top-k", type=int, default=5)
    ps.set_defaults(func=cmd_search)

    pa = sub.add_parser("ask", help="retrieve, then answer with the chat model")
    pa.add_argument("query")
    pa.add_argument("--top-k", type=int, default=4)
    pa.add_argument("--max-tokens", type=int, default=700)
    pa.add_argument("-v", "--verbose", action="store_true")
    pa.set_defaults(func=cmd_ask)

    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    sys.exit(args.func(args) or 0)
