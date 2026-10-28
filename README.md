# Multi-Grappler / Speed Balls

A Godot 4.3 browser game with a level editor and WebRTC multiplayer for 2–8 players.

## Test locally:

1. Install Node.js 20.12 or newer. Start the room/signaling service:

   ```sh
   cd server
   npm ci
   npm start
   ```

2. Open `project.godot` in Godot 4.3 and export the **Web** preset. Install the matching export templates if prompted. Serve the export through HTTP, for example from the repository root:

   ```sh
   python -m http.server 8000 --directory build/web
   ```

3. Visit `http://localhost:8000` in two browser tabs.

