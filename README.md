# multi_grappler

Small Godot 4.3 project migrated from the neighboring `grappler` project. The
original project was only read and remains unchanged.

Open `project.godot` and press F6 with `base_level.tscn` open, or F5 to run it as
the main scene. The scene contains level 3's baked terrain and LevelSketch
settings, plus the player ball. Enemy and NPC instances and resources are omitted.

## Controls

- A/D or Left/Right: move.
- Aim with the mouse; hold Space to grapple, release to detach.
- Hold the left mouse button to charge the mace; release to attack. Hitting
  terrain applies recoil.

## Included files

- `scenes/player_ball.tscn` and `scripts/ball.gd`: movement, grapple, mace,
  camera, squash/stretch, and health UI.
- `scripts/enemy_health_bar.gd`: shared drawing widget used for both the player's
  health and charge meter. It has no enemy dependencies.
- Three original images: main ball, attack mace, and heart.
- `scripts/level_sketch.gd`, `scripts/level_sketch_visual.gd`, and
  `addons/level_sketch/`: terrain drawing/baking tools and runtime visuals.

The ball scene preserves the original physics contact-reporting setting (zero).
Enabling contact reporting activates the script's much stronger grounded movement
branch and changes the movement feel. The old intro-scene camera branch was removed.
Procedural attack audio has been removed; the ball currently has no sound effects.

## Drawing terrain

The Level Sketch editor plugin is enabled in Project Settings > Plugins. Select
the LevelSketch node in the 2D editor, choose Line or Ground, draw with the left
mouse button, then Bake to create terrain visuals and collision. Baked terrain
lives under GeneratedLevel. The original level 3 has already consumed its source
strokes during baking, so the copied LevelSketch starts with no pending strokes.
You can draw additional terrain or delete baked TerrainStroke nodes to clear it.

## Browser export

Install the export templates matching your Godot version using Editor > Manage
Export Templates. In Project > Export, use the Web preset and export to
`build/web/index.html` (create the directory first). The preset exports the main
scene and dependencies, and disables threads to simplify hosting. Serve the
exported directory over HTTP for local testing, and HTTPS in production; opening
the HTML file directly is insufficient.

The project uses GDScript and the Compatibility renderer. LevelSketch bakes in
the editor; the browser only needs the baked terrain and its drawing script.
Its speckles and numerous thick polylines still need profiling on slower devices.
The source images are small on disk but retain their original dimensions, including
a 1797-by-1797 ball; downscaling copies is an option once visual quality is checked.

This migration is a local single-player sandbox. Multiplayer spawning, input
authority, remote-player cameras/UI, and physics replication are not implemented.
For browser multiplayer use WebSocket clients with a server, or WebRTC; ENet/UDP
is unavailable in browser exports. Do not assume peer physics simulations remain
in sync without authoritative state updates.

References: [Godot Web export](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_web.html)
and [WebSockets](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html).

## Validation

Godot 4.3 headless editor import completed without script or resource errors.
A runtime smoke check passed scene loading, terrain collision, keyboard movement,
health changes, mouse charge/release, mace cleanup, and LevelSketch baking.
A browser export has not been run.
