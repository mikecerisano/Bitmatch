#!/usr/bin/env python3
"""Create disposable, clearly synthetic BitMatch screenshot/demo data."""
import hashlib
import json
import tempfile
from pathlib import Path

root = Path(tempfile.mkdtemp(prefix="BitMatch-Demo-", dir="/tmp"))
source = root / "Demo Card"
source.mkdir()
for name in ("Backup A", "Backup B"):
    (root / name).mkdir()
manifest = {}
for index in range(1, 13):
    name = f"DEMO_{index:04d}.bin"
    # Test payloads, deliberately not masquerading as camera images.
    block = (f"BitMatch synthetic demonstration file {index:04d}\n".encode() * 2048)
    payload = (block * 24)[:2 * 1024 * 1024]
    (source / name).write_bytes(payload)
    manifest[name] = {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
(root / "expected-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(root)
print(f"Source: {source}")
print(f"Destination A: {root / 'Backup A'}")
print(f"Destination B: {root / 'Backup B'}")
print("Synthetic local test data only; not a hardware reliability test.")
