#!/usr/bin/env python3
"""Rebuild the throwaway Turn appearance study with Apple's native renderer.

Run: python3 docs/design/identity/turn-appearances-prototype/render.py
Requires Xcode 27 / Icon Composer 27. No simulator is booted.
"""
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent
developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
TOOL = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
TINTS = {"copper": 0.08, "green": 0.50, "blue": 0.62, "violet": 0.82}
renders = ROOT / "renders"
renders.mkdir(exist_ok=True)
manifest = {"renderer": json.loads(subprocess.check_output([str(TOOL), "--version"], text=True)), "tintStrength": 0.7, "tints": TINTS, "renders": []}
for generation in (26, 27):
    modes = [("Default", None), ("Dark", None)]
    modes += [(mode, tint) for mode in ("TintedLight", "TintedDark") for tint in TINTS]
    for mode, tint in modes:
        for size, scale in ((512, 1), (60, 2), (32, 2)):
            stem = f"{generation}-{mode}" + (f"-{tint}" if tint else "")
            stem += f"-{size}" if size != 512 else ""
            output = renders / f"{stem}.png"
            command = [str(TOOL), str(ROOT / "Turn.icon"), "--export-image", "--output-file", str(output), "--platform", "iOS", "--rendition", mode, "--width", str(size), "--height", str(size), "--scale", str(scale), "--design-generation", str(generation)]
            if tint:
                command += ["--tint-color", str(TINTS[tint]), "--tint-strength", "0.7"]
            subprocess.run(command, check=True, capture_output=True, text=True)
            manifest["renders"].append({"file": output.name, "generation": generation, "appearance": mode, "tint": tint, "points": size, "scale": scale})
        print(f"Rendered iOS {generation}: {mode} {tint or ''}", flush=True)
(ROOT / "render-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
with zipfile.ZipFile(ROOT / "Turn.icon.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((ROOT / "Turn.icon").rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(ROOT))
