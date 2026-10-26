# Multi-Grappler / Speed Balls

A Godot 4.3 browser game with a level editor and WebRTC multiplayer for 2–8 players.

## Play together locally

1. Install Node.js 20 or newer. Start the room/signaling service:

   ```sh
   cd server
   npm ci
   npm start
   ```

2. Open `project.godot` in Godot 4.3 and export the **Web** preset. Install the matching export templates if prompted. Serve the export through HTTP, for example from the repository root:

   ```sh
   python -m http.server 8000 --directory build/web
   ```

3. Visit `http://localhost:8000` in two browser tabs. In **Level Editor**, draw a playable level, place its spawn, and copy the `MG1-` level code.
4. Choose **Host Game**, paste that level code, choose a player limit, and create the room. The level starts immediately. Copy the displayed **8-digit room code**.
5. In the other tab, choose **Join Game** and enter the room code. Both tabs automatically use the configured room service (`ws://localhost:9080` by default). Click the code at the top of the game to copy it.

Each player has their own controls, camera and HUD. Players simulate their own movement and send snapshots to the host; the host distributes movement and grapple state at 30 Hz using Godot's `MultiplayerSynchronizer`. Remote movement is smoothed. Late joiners receive the host's level and existing players. Falling outside the level respawns a player. Opening a multiplayer menu locks that player's controls while the game continues. Leaving from the host's menu, closing their browser, or losing their connection ends the session; guests return to the title screen. A killed process/network failure is detected after WebRTC disconnect or the service's heartbeat timeout (up to about 20 seconds).

WebRTC is built into Godot's web export. To host/join from the native Godot editor or a desktop executable, install the matching [webrtc-native GDExtension](https://github.com/godotengine/webrtc-native); without it, use browser tabs. Tutorial and editor playtests still work natively.

## Internet play and Cloudflare TURN

The room service introduces players using WebSocket messages (room codes, level codes, SDP and ICE). Gameplay uses WebRTC data channels in a host/guest topology; the host relays guest state to other guests. The Node service never relays gameplay packets. Room codes are random, collision checked, and exist only while the host is connected; restarting the service ends its rooms. Run one signaling instance unless you add shared room storage/routing.

Deploy `server/` on a service that supports persistent Node processes and WebSockets, with HTTPS/WSS termination in front of it. `GET /health` provides a health check. Set `ALLOWED_ORIGINS` to your game's browser origin(s), separated by commas. The game and signaling service can use different domains. A static game host or Cloudflare TURN alone does **not** run this Node signaling service.

For players on restrictive networks, configure TURN. The service already supports [Cloudflare Realtime TURN](https://developers.cloudflare.com/realtime/turn/generate-credentials/):

1. Create a TURN key in Cloudflare Realtime, and obtain its key ID and associated API token.
2. Set these **on the signaling server**, using your hosting provider's environment/secrets configuration:

   ```text
   CLOUDFLARE_TURN_KEY_ID=<TURN key ID>
   CLOUDFLARE_TURN_API_TOKEN=<associated API token>
   TURN_TTL_SECONDS=86400
   ALLOWED_ORIGINS=https://your-game.example
   ```

   The backend generates expiring ICE credentials for each joining browser. The long-lived key/token never goes to the game. Credentials default to 24 hours; sessions needing TURN must finish within the configured lifetime. Automatic credential refresh, ICE restart and reconnection are not implemented yet. Without Cloudflare credentials the service uses public STUN, which is sufficient for local testing and some direct connections, but cannot guarantee connectivity across NATs/firewalls. Alternatively, set `ICE_SERVERS_JSON` to an array of your own WebRTC ICE server definitions.

3. Point the game at the public `wss://` room service. Set `network/signaling_url` in `project.godot` before exporting, or set this in the web export's HTML head. Players do not need to enter a server address:

   ```html
   <script>window.MULTI_GRAPPLER_SIGNALING_URL = "wss://rooms.your-game.example";</script>
   ```

Use HTTPS for the public game and WSS for its room service. `localhost` in another player's browser refers to their own computer. Never embed Cloudflare API tokens in a level code, Godot resource or HTML page. `server/.env.example` lists available configuration variables; supply them through the process environment (the server does not load `.env` files).

This first multiplayer version supports shared levels, movement and grapple visibility. Balls are locally simulated and do not collide with other players. Competitive PvP damage, attack animation replication, anti-cheat, host migration and reconnect are separate work.

## Validation

```sh
godot --headless --path . --script tests/level_editor_tests.gd
godot --headless --path . --script tests/menu_navigation_tests.gd
godot --headless --path . --script tests/multiplayer_tests.gd
cd server
npm test
```

The browser smoke test opens three real clients, verifies WebRTC connections and replicated movement, then checks guest and host teardown. It uses local ICE with no TURN account or cloud deployment:

```sh
# From the repository root, with Godot's matching Web templates installed:
python tests/export_multiplayer_browser.py --godot godot
cd server
npx playwright install chromium
npm run test:browser
```

The exporter makes a temporary copy with a test entry scene, leaving the game's main scene unchanged. Its output is ignored under `build/multiplayer-browser`. Use `--template /path/to/web_nothreads_debug.zip` if templates are outside Godot's normal data directory. `CHROME_PATH` can select an already installed Chrome executable, and `BROWSER_TEST_DIR` can select a different fixture export directory. The test needs port 9080 available.
