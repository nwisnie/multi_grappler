# Multi-Grappler

My attempt at making web-game a game with basic mutliplayer using the Godot engine. The base code and assets a from a bigger project that I was working on that I'll probably scrap. I made really cool movement though, so I still wanted to use that in a game.

## In-game level editor

Run the project and click **Level Editor** in the upper right. The original demo
remains available through **Back to game**; the editor draft survives that visit.

The board has 100 × 100 cells, each 120 world units wide (about one player).
Terrain is one cell thick. All placement is rigidly snapped to the grid.

- **Line:** click two grid intersections.
- **Curve:** click start, end, then a third intersection the curve passes through.
- **Select / move:** drag an endpoint circle or a curve's gold diamond. All
  endpoints sharing a joint move together. Click a segment and press Delete to
  remove it. Spawn markers and grapple orbs can also be dragged or deleted.
- **Spawn / Grapple orb:** click a cell center. One spawn and up to 128 orbs are
  supported, with up to 1,024 terrain segments.
- **Erase:** click a segment, spawn, or orb to remove it.
- Scroll to zoom at the cursor; middle/right drag to pan; **F** fits the board.
  Escape cancels unfinished placement or a move. Ctrl/Cmd+Z undoes;
  Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y redoes. Clear and imports are also undoable.

**Playtest** requires a spawn clear of terrain. Movement and grappling use the
existing player controls. Leaving the board respawns a fresh player; **Restart**
does the same. **Back to editor** restores the draft and editor camera.

### Sharing and persistence

Use **Export code**, copy the entire `MG1-...` text, and send it to another player.
They can paste it into **Import code**. The code contains the level: no upload,
account, level-hosting service, or downloaded level file is needed. Codes grow
with the number of segments; the dialog shows their character count. Browser
clipboard permissions can block the Copy button; the selectable text also
supports ordinary Ctrl/Cmd+C and Ctrl/Cmd+V.

**Drafts exist only in memory. Export and retain a code before closing or
refreshing the game.** There is no automatic save or downloadable-file workflow.

The portable `LevelDocument` contains integer grid points, terrain definitions,
an optional spawn, and orb cells. `LevelCodec.encode_level` / `decode_level` use
a versioned binary payload compressed with DEFLATE and encoded as Base64.
Straight segments use five payload bytes; curves use seven. Sampled curves,
generated visuals, and collision nodes are rebuilt rather than serialized.
Imports validate counts, coordinates, versions, curve bounds, and a bounded
decompressed payload before replacing the draft. Multiplayer is not implemented
yet; a future network session can exchange this same portable level format.

### Validation (Godot 4.3)

With the Godot executable on your PATH:

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/level_editor_tests.gd
godot --headless --path . --script res://tests/level_geometry_stress.gd
godot --headless --path . --export-debug Web build/web/index.html
node tests/web_smoke.mjs
```

Create `build/web` before exporting and install the Godot 4.3 export templates.
The Web preset includes the game shell, editor, custom playtest, and original
demo. Serve the exported directory over HTTP locally or HTTPS in production.

The browser smoke test uses installed Chrome and Node.js without npm dependencies,
serves the export locally, and saves screenshots under `build/screenshots`.
Override `CHROME_PATH` if Chrome is installed elsewhere. For native rendering,
run `godot --path . --script res://tests/desktop_smoke.gd --resolution 1280x720`;
it saves desktop screenshots in the same directory and exits automatically.

## Script folders

- `scripts/player/`: player movement, combat, and grapple controls.
- `scripts/grapple/`: grapple orbs, targeting cursor, and rope effects.
- `scripts/levels/`: level data, sharing codes, terrain geometry/rendering, custom
  playtests, and sky background.
- `scripts/editor/`: in-game level editor, toolbar buttons, and LevelSketch tools.
- `scripts/ui/`: game navigation and shared health/charge bars.

Godot's LevelSketch plugin remains in `addons/level_sketch/`; validation scripts
remain in `tests/`. Generated exports, screenshots, browser profiles, and logs
under `build/` are ignored; its `.gdignore` file is tracked to keep Godot from
importing those generated files.
