#!/usr/bin/env python3
"""Export the 112 pt launch icon with Xcode 27's Icon Composer renderer.

Run from any directory. The OS 26 rendition is shared by the storyboard and
SwiftUI loader; the native app icon is rendered by whichever OS runs the app.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "App/Aujour/Assets.xcassets/LaunchIcon.imageset"
DEVELOPER = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
ICTOOL = DEVELOPER.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"

images = []
for rendition, name in [("Default", "light"), ("Dark", "dark")]:
    for scale in (1, 2, 3):
        filename = f"turn-{name}@{scale}x.png"
        subprocess.run(
            [
                str(ICTOOL), str(ROOT / "App/Aujour/AppIcon.icon"),
                "--export-image", "--output-file", str(ASSETS / filename),
                "--platform", "iOS", "--rendition", rendition,
                "--width", "112", "--height", "112", "--scale", str(scale),
                "--design-generation", "26",
            ],
            check=True,
        )
        image = {"filename": filename, "idiom": "universal", "scale": f"{scale}x"}
        if name == "dark":
            image["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(image)

(ASSETS / "Contents.json").write_text(
    json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
)
