#!/usr/bin/env python3
"""Read signed build provenance without reading credentials or customer records."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("app", type=pathlib.Path)
args = parser.parse_args()
app = args.app.resolve()
manifest = json.loads((app / "Contents/Resources/build-manifest.json").read_text())
with (app / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
runtime = pathlib.Path(info["SalesPilotWorkspaceRoot"])
drift = []
for name, expected in manifest["sourceFiles"].items():
    # Native code is compiled into the app; only engine sources run from this directory.
    if name.startswith("engine/") and not pathlib.Path(name).name.startswith(("test-", "bench-")):
        path = runtime / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        if actual != expected:
            drift.append(name)
verification = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                              capture_output=True)
print(json.dumps({"schemaVersion": 1, "sourceRevision": manifest["sourceRevision"],
                  "sourceModified": manifest["sourceModified"],
                  "binarySha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "signatureVerified": verification.returncode == 0,
                  "runtimeSourceDrift": drift,
                  "scope": "Build identity and source integrity only; not compliance approval or model inventory"}, indent=2))
raise SystemExit(1 if verification.returncode or drift else 0)
