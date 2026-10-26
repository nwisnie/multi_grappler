"""Export a test-only entry scene without changing the game's main scene."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--godot", default="godot")
parser.add_argument("--template", help="Optional web_nothreads_debug.zip path")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = repo / "build" / "multiplayer-browser" / "index.html"
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="multi-grappler-browser-") as directory:
    staging = Path(directory)
    for name in ("assets", "scripts", "scenes", "tests", "addons"):
        shutil.copytree(repo / name, staging / name)
    for name in ("base_level.tscn", "icon.svg", "icon.svg.import", "project.godot", "export_presets.cfg"):
        shutil.copy2(repo / name, staging / name)
    # Reuse asset imports when available, so the editor can load the theme at startup.
    if (repo / ".godot" / "imported").is_dir():
        shutil.copytree(repo / ".godot" / "imported", staging / ".godot" / "imported")
    project = staging / "project.godot"
    contents = project.read_text().replace("res://scenes/game_shell.tscn", "res://tests/multiplayer_browser.tscn")
    contents = contents.replace('enabled=PackedStringArray("res://addons/level_sketch/plugin.cfg")', "enabled=PackedStringArray()")
    project.write_text(contents)
    presets = staging / "export_presets.cfg"
    contents = presets.read_text().replace("addons/*,tests/*,build/*,server/*,docs/*", "addons/*,build/*,server/*,docs/*")
    if args.template:
        template = Path(args.template).resolve().as_posix()
        contents = contents.replace('custom_template/debug=""', f'custom_template/debug="{template}"')
    presets.write_text(contents)
    subprocess.run([args.godot, "--headless", "--path", directory, "--import"], check=True)
    subprocess.run([args.godot, "--headless", "--path", directory, "--export-debug", "Web", str(output)], check=True)
print(f"Browser fixture exported to {output}")
