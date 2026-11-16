# Multi-Grappler / Speed Balls

My attempt at making a web-game game with basic mutliplayer using the Godot engine. The base code and assets a from a bigger project that I was working on that I'll probably scrap. It had really cool movement though, so I still wanted to use that in a game.

This game has a level editor and basic mutliplayer for 2-8 players using WebRTC

In the level editor, **Race checkpoint** lets you choose **Hoop** or **Line**.
Click an existing checkpoint to change its shape, order, or finish status. New
lines use two cell centers; **Set endpoints** replaces those points, and **Select**
lets you drag either endpoint or move the whole line. **Spawn** also supports
lines: **Spawn on line** sets the player's starting position from endpoint A (0%)
to endpoint B (100%). Lines count ball contact anywhere along their finite length.

**Level Editor** opens a submenu with **Browse Levels** and **Create New**. Players can
publish a playable level with **Upload** inside the editor, then browse and play
community levels. Published levels are stored in Cloudflare D1, with a global maximum
of 100. Once full, the library rejects new uploads and preserves existing levels.

Sign in and choose **Save** next to a community level's **Play** button, or
**Save Level** in the pause menu, to keep a playable copy on this device or browser. Saved levels
move out of the community list and into **Saved Levels**, available at the top
right of the browser. **My Levels** lists levels published by the signed-in
account. Both views support playing, and saved copies need no library download
while signed in. **Host Game** offers **Browse Levels**, **Saved Levels**, and **My Levels**
to select a lobby level. Selecting a level returns to the host form and keeps
the game name, visibility, and player limit. Saves persist locally for each account;
signing out hides them, and signing back into the same account restores them.
Earlier device saves can be brought into the signed-in account with **Import earlier
saved levels** in Saved Levels. Browsing, playing community levels, and multiplayer
remain available while signed out.

Uploading requires a username/password account. **Settings** provides **Sign in /
Create account** and **Sign out**. Choosing **Upload** while signed out opens the same
account prompt, then returns to the upload form. The creator name comes from the
signed-in account. Browsing, playing, editing, and multiplayer remain available without
an account.

For D1 setup, deployment, and local level publishing, see
[the Cloudflare backend instructions](server/cloudflare/README.md#set-up-d1-for-level-publishing).
Use the Cloudflare Worker locally for these features.

## To Test Locally:

1. Install Node.js 22 or newer. Start the Worker with a local D1 database:

   ```sh
   cd server/cloudflare
   npm ci
   npm run db:local
   npm run dev
   ```

2. Open `project.godot` in Godot 4.3 and export the **Web** preset. Install the matching export templates if prompted. Serve the export through HTTP, for example from the repository root:

   ```sh
   python -m http.server 8000 --directory build/web
   ```

3. Visit `http://localhost:8000` in two browser tabs.

The original `cd server && npm start` service is still available for signaling-only
development; level publishing and browsing require the Worker above.

## Cloudflare:

The production signaling backend uses Workers and one SQLite-backed Durable Object per lobby. Any bozo can host a lobby. Gameplay uses Godot's WebRTC multiplayer and MultiplayerSynchronizer. I will probably use GitHub Pages to serve the game.
