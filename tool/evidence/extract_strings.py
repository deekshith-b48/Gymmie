#!/usr/bin/env python3
"""Isolate application-specific string constants from a Dart AOT snapshot.

libapp.so stores every string constant used by the compiled program, framework and
packages included. We subtract every literal found in the Flutter framework, Dart SDK
and (when present) pub-cache package sources. What remains is predominantly app code:
UI copy, API paths, JSON field names, error messages, shared-preference keys.

Usage: extract_strings.py <libapp.so> <out_dir> <corpus_root> [<corpus_root> ...]
"""
import os
import re
import sys

LIT_RE = re.compile(
    r"""(?:r)?(?:'''(?:[^\\]|\\.)*?'''|\"\"\"(?:[^\\]|\\.)*?\"\"\"|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""",
    re.S,
)
INTERP_RE = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")
ESC_RE = re.compile(r"\\(.)", re.S)
ESC_MAP = {"n": "\n", "t": "\t", "r": "\r", "$": "$", "'": "'", '"': '"', "\\": "\\"}


def unescape(s):
    return ESC_RE.sub(lambda m: ESC_MAP.get(m.group(1), m.group(1)), s)


def literal_pieces(lit):
    raw = lit.startswith("r")
    body = lit[1:] if raw else lit
    for q in ("'''", '"""', "'", '"'):
        if body.startswith(q) and body.endswith(q) and len(body) >= 2 * len(q):
            body = body[len(q):-len(q)]
            break
    pieces = [body] if raw else INTERP_RE.split(body)
    out = []
    for p in pieces:
        p = p if raw else unescape(p)
        if p:
            out.append(p)
            for line in p.split("\n"):
                if line:
                    out.append(line)
    return out


def build_corpus(roots):
    corpus = set()
    n = 0
    for root in roots:
        for dp, dn, fn in os.walk(root):
            dn[:] = [d for d in dn if d not in (".git", "test", "build", "example")]
            for f in fn:
                if not f.endswith((".dart", ".arb")):
                    continue
                try:
                    txt = open(os.path.join(dp, f), encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                n += 1
                if f.endswith(".arb"):
                    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', txt):
                        corpus.add(unescape(m.group(1)))
                    continue
                for m in LIT_RE.finditer(txt):
                    for p in literal_pieces(m.group(0)):
                        corpus.add(p)
    return corpus, n


def main():
    so, out, *roots = sys.argv[1:]
    os.makedirs(out, exist_ok=True)
    data = open(so, "rb").read()
    found = sorted({m.group(0).decode("latin-1") for m in re.finditer(rb"[\x20-\x7e\n\t]{4,}", data)})
    corpus, nfiles = build_corpus(roots)
    app = [s for s in found if s not in corpus and s.strip() not in corpus]
    with open(os.path.join(out, "all_ascii.txt"), "w") as fh:
        fh.write("\n".join(found))
    with open(os.path.join(out, "app_candidates.txt"), "w") as fh:
        fh.write("\n".join(app))
    print(f"corpus files={nfiles} literals={len(corpus)} snapshot_strings={len(found)} candidates={len(app)}")


if __name__ == "__main__":
    main()
