"use strict";
// Run after tests/export_multiplayer_browser.py. Never uses the public TURN service.
const assert = require("node:assert/strict");
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");
const { createSignalingServer } = require("./signaling");

(async () => {
  const directory = process.env.BROWSER_TEST_DIR || path.join(__dirname, "../build/multiplayer-browser");
  const types = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png" };
  const files = http.createServer((req, res) => {
    const name = path.basename(new URL(req.url, "http://localhost").pathname) || "index.html";
    const file = path.join(directory, name);
    if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  });
  const signaling = createSignalingServer({ getIceServers: async () => [] });
  let browser;
  try {
    await new Promise(resolve => signaling.server.listen(9080, "127.0.0.1", resolve));
    await new Promise(resolve => files.listen(0, "127.0.0.1", resolve));
    browser = await chromium.launch({
      headless: true,
      executablePath: process.env.CHROME_PATH || undefined,
      args: ["--no-sandbox", "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--autoplay-policy=no-user-gesture-required"],
    });
    const errors = [];
    const url = `http://127.0.0.1:${files.address().port}/index.html`;
    async function page(query) {
      const tab = await browser.newPage({ viewport: { width: 1280, height: 720 } });
      tab.on("console", msg => {
        if (msg.type() === "error" && !msg.text().includes("favicon")) errors.push(`${query}: ${msg.text()}`);
      });
      tab.on("pageerror", error => errors.push(error.message));
      await tab.goto(url + query);
      return tab;
    }
    async function state(tab) { return tab.evaluate(() => window.multiplayerState); }
    async function waitPlayers(tab, count) {
      await tab.waitForFunction(count => window.multiplayerState && !window.multiplayerState.loading && Object.keys(window.multiplayerState.players).length === count, count, { timeout: 30000 });
      const value = await state(tab);
      assert.equal(value.error, "");
      assert.equal(Object.values(value.players).filter(p => p.local && p.camera).length, 1);
      assert.equal(value.room_card_fits, true);
      assert.equal(value.room_card_text, value.room);
      assert.equal(value.loading_seen, true);
      assert.equal(Object.values(value.players).every(p => p.name_upright && p.name_above), true);
    }
    const menus = await page("?role=menus");
    await menus.waitForFunction(() => window.multiplayerState && window.multiplayerState.host_dialog_fits);
    if (process.env.BROWSER_SCREENSHOT) await menus.screenshot({ path: process.env.BROWSER_SCREENSHOT });
    await menus.close();
    console.log("PASS: host setup fits the browser viewport");
    const host = await page("?role=host");
    await host.waitForFunction(() => window.multiplayerState && /^\d{8}$/.test(window.multiplayerState.room), null, { timeout: 30000 });
    const room = (await state(host)).room;
    const guest = await page(`?role=guest&room=${room}`);
    await Promise.all([waitPlayers(host, 2), waitPlayers(guest, 2)]);
    const third = await page(`?role=guest&room=${room}`);
    await Promise.all([waitPlayers(host, 3), waitPlayers(guest, 3), waitPlayers(third, 3)]);
    if (process.env.BROWSER_GAME_SCREENSHOT) await host.screenshot({ path: process.env.BROWSER_GAME_SCREENSHOT });
    console.log("PASS: three browsers connect through WebRTC, receive the host's level and own one camera each");
    const guestState = await state(guest);
    const guestId = Object.keys(guestState.players).find(id => guestState.players[id].local);
    const start = guestState.players[guestId].x;
    await guest.bringToFront();
    await guest.locator("canvas").focus();
    await guest.keyboard.down("d");
    await guest.waitForFunction(({ id, start }) => window.multiplayerState.players[id].x > start + 80, { id: guestId, start });
    await guest.keyboard.up("d");
    await Promise.all([host, third].map(tab => tab.waitForFunction(({ id, start }) => window.multiplayerState.players[id].x > start + 60, { id: guestId, start })));
    console.log("PASS: guest movement reaches the host and another guest via MultiplayerSynchronizer");
    await guest.mouse.move(640, 650);
    await guest.keyboard.down("Space");
    await Promise.all([host, third].map(tab => tab.waitForFunction(id => window.multiplayerState.players[id].grapple, guestId)));
    await guest.keyboard.up("Space");
    console.log("PASS: guest grapple state reaches the host and another guest");
    await guest.evaluate(() => { window.multiplayerCommand = "respawn"; });
    await Promise.all([host, guest].map(tab => tab.waitForFunction(({ id, start }) => Math.abs(window.multiplayerState.players[id].x - start) < 40, { id: guestId, start })));
    console.log("PASS: respawn preserves the player and replicates its new position");
    const hostStart = (await state(host)).players["1"].x;
    await host.bringToFront();
    await host.locator("canvas").focus();
    await host.keyboard.down("d");
    await host.waitForFunction(start => window.multiplayerState.players["1"].x > start + 80, hostStart);
    await host.keyboard.up("d");
    await guest.waitForFunction(start => window.multiplayerState.players["1"].x > start + 60, hostStart);
    console.log("PASS: host movement reaches guests");
    await guest.evaluate(() => { window.multiplayerCommand = "pause"; });
    await guest.waitForFunction(() => window.multiplayerState.menu);
    assert.equal((await state(guest)).paused, false);
    assert.equal((await state(guest)).players[guestId].locked, true);
    await guest.evaluate(() => { window.multiplayerCommand = "resume"; });
    await guest.waitForFunction(() => !window.multiplayerState.menu);
    console.log("PASS: multiplayer menus keep the network running");
    const thirdState = await state(third);
    const thirdId = Object.keys(thirdState.players).find(id => thirdState.players[id].local);
    const thirdStart = thirdState.players[thirdId].x;
    await third.bringToFront();
    await third.locator("canvas").focus();
    await third.keyboard.down("d");
    await third.waitForFunction(({ id, start }) => window.multiplayerState.players[id].x > start + 30, { id: thirdId, start: thirdStart });
    await third.close();
    await Promise.all([waitPlayers(host, 2), waitPlayers(guest, 2)]);
    console.log("PASS: closing a guest removes its replicated player");
    if (process.env.HOST_EXIT_MODE === "menu") {
      await host.evaluate(() => { window.multiplayerCommand = "leave"; });
    } else await host.close();
    await guest.waitForFunction(() => window.multiplayerState && window.multiplayerState.error.includes("host"), null, { timeout: 30000 });
    assert.equal(Object.keys((await state(guest)).players).length, 0);
    assert.equal(signaling.rooms.size, 0);
    assert.deepEqual(errors, []);
    console.log("PASS: closing the host ends the session and destroys the room; no browser/Godot errors");
  } finally {
    if (browser) await browser.close();
    await signaling.close();
    await new Promise(resolve => files.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
