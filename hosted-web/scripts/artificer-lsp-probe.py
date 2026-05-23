#!/usr/bin/env python3
import argparse
import json
import os
import select
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

SEVERITY_MAP = {1: "error", 2: "warning", 3: "information", 4: "hint"}
SYMBOL_KIND_MAP = {
    1: "file",
    2: "module",
    3: "namespace",
    4: "package",
    5: "class",
    6: "method",
    7: "property",
    8: "field",
    9: "constructor",
    10: "enum",
    11: "interface",
    12: "function",
    13: "variable",
    14: "constant",
    15: "string",
    16: "number",
    17: "boolean",
    18: "array",
    19: "object",
    20: "key",
    21: "null",
    22: "enumMember",
    23: "struct",
    24: "event",
    25: "operator",
    26: "typeParameter",
}

SERVER_BY_SUFFIX = {
    ".py": (["pyright-langserver", "--stdio"], "python"),
    ".js": (["typescript-language-server", "--stdio"], "javascript"),
    ".jsx": (["typescript-language-server", "--stdio"], "javascriptreact"),
    ".ts": (["typescript-language-server", "--stdio"], "typescript"),
    ".tsx": (["typescript-language-server", "--stdio"], "typescriptreact"),
    ".mts": (["typescript-language-server", "--stdio"], "typescript"),
    ".cts": (["typescript-language-server", "--stdio"], "typescript"),
    ".mjs": (["typescript-language-server", "--stdio"], "javascript"),
    ".cjs": (["typescript-language-server", "--stdio"], "javascript"),
    ".go": (["gopls"], "go"),
    ".rs": (["rust-analyzer"], "rust"),
    ".c": (["clangd", "--background-index=false", "--pch-storage=memory"], "c"),
    ".cc": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
    ".cpp": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
    ".cxx": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
    ".h": (["clangd", "--background-index=false", "--pch-storage=memory"], "c"),
    ".hh": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
    ".hpp": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
    ".hxx": (["clangd", "--background-index=false", "--pch-storage=memory"], "cpp"),
}


def path_to_uri(path: Path) -> str:
    return path.resolve().as_uri()


class LspClient:
    def __init__(self, command):
        self.proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self.next_id = 1

    def send(self, payload):
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        header = f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii")
        assert self.proc.stdin is not None
        self.proc.stdin.write(header)
        self.proc.stdin.write(raw)
        self.proc.stdin.flush()

    def request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        return request_id

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def read_message(self, timeout=0.1):
        assert self.proc.stdout is not None
        ready, _, _ = select.select([self.proc.stdout], [], [], timeout)
        if not ready:
            return None
        headers = {}
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return None
            if line in (b"\r\n", b"\n"):
                break
            key, _, value = line.decode("utf-8", "replace").partition(":")
            headers[key.strip().lower()] = value.strip()
        length = int(headers.get("content-length", "0"))
        if length <= 0:
            return None
        body = self.proc.stdout.read(length)
        if not body:
            return None
        try:
            return json.loads(body.decode("utf-8", "replace"))
        except Exception:
            return None

    def close(self):
        try:
            self.request("shutdown", {})
        except Exception:
            pass
        try:
            self.notify("exit", {})
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=1.0)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def pick_server(file_path: Path):
    override = os.environ.get("ARTIFICER_LSP_SERVER_CMD", "").strip()
    if override:
        return shlex.split(override), os.environ.get("ARTIFICER_LSP_LANGUAGE_ID", "plaintext") or "plaintext"
    suffix = file_path.suffix.lower()
    if suffix not in SERVER_BY_SUFFIX:
        return None, None
    command, language_id = SERVER_BY_SUFFIX[suffix]
    if shutil.which(command[0]) is None:
        return None, None
    return command, language_id


def compact_range(range_obj):
    start = (range_obj or {}).get("start", {})
    end = (range_obj or {}).get("end", {})
    return {
        "start_line": int(start.get("line", 0)) + 1,
        "start_character": int(start.get("character", 0)) + 1,
        "end_line": int(end.get("line", 0)) + 1,
        "end_character": int(end.get("character", 0)) + 1,
    }


def simplify_diagnostic(item):
    return {
        "severity": SEVERITY_MAP.get(item.get("severity"), "unknown"),
        "message": str(item.get("message", "")).strip(),
        "range": compact_range(item.get("range") or {}),
        "source": str(item.get("source", "")).strip(),
        "code": str(item.get("code", "")).strip(),
    }


def flatten_symbols(symbols, max_symbols):
    flat = []

    def walk(items):
        for item in items or []:
            if not isinstance(item, dict):
                continue
            rng = item.get("selectionRange") or item.get("range") or {}
            flat.append(
                {
                    "name": str(item.get("name", "")).strip(),
                    "kind": SYMBOL_KIND_MAP.get(item.get("kind"), "unknown"),
                    "range": compact_range(rng),
                }
            )
            if len(flat) >= max_symbols:
                return
            walk(item.get("children") or [])
            if len(flat) >= max_symbols:
                return

    walk(symbols)
    return flat[:max_symbols]


def build_summary(path_value, diagnostics, symbols, server_name):
    errors = sum(1 for item in diagnostics if item.get("severity") == "error")
    warnings = sum(1 for item in diagnostics if item.get("severity") == "warning")
    top_symbols = ", ".join(sym.get("name", "") for sym in symbols[:4] if sym.get("name")) or "none"
    return f"{path_value}: {errors} errors, {warnings} warnings, top symbols: {top_symbols} (via {server_name})"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("workspace_root")
    parser.add_argument("file_path")
    parser.add_argument("--max-diagnostics", type=int, default=6)
    parser.add_argument("--max-symbols", type=int, default=8)
    parser.add_argument("--wait-seconds", type=float, default=0.8)
    args = parser.parse_args()

    workspace_root = Path(args.workspace_root).expanduser().resolve()
    file_path = Path(args.file_path).expanduser().resolve()
    command, language_id = pick_server(file_path)
    rel_path = os.path.relpath(file_path, workspace_root) if file_path.is_absolute() else str(file_path)

    if command is None:
        print(
            json.dumps(
                {
                    "success": False,
                    "reason": "no-server",
                    "workspace_root": str(workspace_root),
                    "file": rel_path,
                },
                separators=(",", ":"),
            )
        )
        return 0

    if not file_path.exists() or not file_path.is_file():
        print(
            json.dumps(
                {
                    "success": False,
                    "reason": "missing-file",
                    "workspace_root": str(workspace_root),
                    "file": rel_path,
                },
                separators=(",", ":"),
            )
        )
        return 0

    text = file_path.read_text(encoding="utf-8", errors="replace")
    client = LspClient(command)
    diagnostics = []
    symbols = []
    pending_symbol_id = None
    uri = path_to_uri(file_path)
    root_uri = path_to_uri(workspace_root)

    try:
        init_id = client.request(
            "initialize",
            {
                "processId": os.getpid(),
                "rootUri": root_uri,
                "workspaceFolders": [{"uri": root_uri, "name": workspace_root.name}],
                "capabilities": {
                    "textDocument": {"publishDiagnostics": {}, "documentSymbol": {}},
                    "workspace": {"workspaceFolders": True},
                },
                "clientInfo": {"name": "artificer-lsp-probe", "version": "1"},
            },
        )

        deadline = time.time() + max(args.wait_seconds, 0.25)
        initialized = False
        while time.time() < deadline:
            msg = client.read_message(timeout=0.05)
            if not msg:
                continue
            if msg.get("id") == init_id:
                initialized = True
                break
        if not initialized:
            raise RuntimeError("initialize-timeout")

        client.notify("initialized", {})
        client.notify(
            "textDocument/didOpen",
            {"textDocument": {"uri": uri, "languageId": language_id, "version": 1, "text": text}},
        )
        pending_symbol_id = client.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})

        deadline = time.time() + max(args.wait_seconds, 0.25)
        while time.time() < deadline:
            msg = client.read_message(timeout=0.05)
            if not msg:
                continue
            if msg.get("method") == "textDocument/publishDiagnostics":
                params = msg.get("params") or {}
                if params.get("uri") == uri:
                    diagnostics = [simplify_diagnostic(item) for item in (params.get("diagnostics") or [])][: args.max_diagnostics]
            if msg.get("id") == pending_symbol_id:
                symbols = flatten_symbols(msg.get("result") or [], args.max_symbols)
                pending_symbol_id = None

        server_name = command[0]
        print(
            json.dumps(
                {
                    "success": True,
                    "workspace_root": str(workspace_root),
                    "file": rel_path,
                    "language_id": language_id,
                    "server": server_name,
                    "diagnostics": diagnostics,
                    "symbols": symbols,
                    "summary": build_summary(rel_path, diagnostics, symbols, server_name),
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    except Exception as exc:
        print(
            json.dumps(
                {
                    "success": False,
                    "reason": "probe-failed",
                    "workspace_root": str(workspace_root),
                    "file": rel_path,
                    "server": command[0],
                    "error": str(exc),
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
