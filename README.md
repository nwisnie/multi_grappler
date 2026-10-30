# Multi-Grappler / Speed Balls

My attempt at making a web-game game with basic mutliplayer using the Godot engine. The base code and assets a from a bigger project that I was working on that I'll probably scrap. It had really cool movement though, so I still wanted to use that in a game.

This game has a level editor and basic mutliplayer for 2-8 players using WebRTC

## To Test Locally:

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

## Cloudflare:

The production signaling backend uses Workers and one SQLite-backed Durable Object per lobby. Any bozo can host a lobby. Gameplay uses Godot's WebRTC multiplayer and MultiplayerSynchronizer. I will probably use GitHub Pages to serve the game.