#!/usr/bin/env python3
import json
import sys


def write_message(payload):
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(raw)
    sys.stdout.buffer.flush()


def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        key, _, value = line.decode("utf-8", "replace").partition(":")
        headers[key.strip().lower()] = value.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body.decode("utf-8", "replace"))


last_open_uri = None
while True:
    msg = read_message()
    if msg is None:
        break
    method = msg.get("method")
    if method == "initialize":
        write_message({"jsonrpc": "2.0", "id": msg.get("id"), "result": {"capabilities": {"documentSymbolProvider": True}}})
    elif method == "initialized":
        continue
    elif method == "textDocument/didOpen":
        doc = (msg.get("params") or {}).get("textDocument") or {}
        last_open_uri = doc.get("uri")
        write_message(
            {
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": {
                    "uri": last_open_uri,
                    "diagnostics": [
                        {
                            "severity": 1,
                            "message": "mock syntax error",
                            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
                            "source": "mock-lsp",
                            "code": "E100",
                        }
                    ],
                },
            }
        )
    elif method == "textDocument/documentSymbol":
        write_message(
            {
                "jsonrpc": "2.0",
                "id": msg.get("id"),
                "result": [
                    {
                        "name": "mockFunction",
                        "kind": 12,
                        "range": {"start": {"line": 0, "character": 0}, "end": {"line": 2, "character": 1}},
                        "selectionRange": {"start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 16}},
                    }
                ],
            }
        )
    elif method == "shutdown":
        write_message({"jsonrpc": "2.0", "id": msg.get("id"), "result": None})
    elif method == "exit":
        break
