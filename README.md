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

## Public multiplayer on Cloudflare

The production signaling backend uses Workers and one SQLite-backed Durable Object per lobby.
Anyone can host a lobby; players do not need Cloudflare accounts. Gameplay still uses Godot's
WebRTC multiplayer and `MultiplayerSynchronizer`. GitHub Pages continues serving the game.

Follow [the Cloudflare setup guide](server/cloudflare/README.md) to install, test, add TURN
secrets, and deploy `rooms.wizkinews.com`. The browser game selects that service automatically
on `wizkinews.com` and `www.wizkinews.com`; localhost keeps using `ws://localhost:9080`.
You must re-export and upload the game after updating the code.

