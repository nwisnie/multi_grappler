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
  // An external local Worker lets the same real-browser assertions cover both backends.
  const signaling = process.env.BROWSER_SIGNALING_URL ? null : createSignalingServer({ getIceServers: async () => [] });
  let browser;
  const sameWindowTabs = process.env.BROWSER_TABS === "1";
  try {
    if (signaling) await new Promise(resolve => signaling.server.listen(9080, "127.0.0.1", resolve));
    await new Promise(resolve => files.listen(Number(process.env.BROWSER_HTTP_PORT || 0), "127.0.0.1", resolve));
    browser = await chromium.launch({
      headless: !sameWindowTabs,
      executablePath: process.env.CHROME_PATH || undefined,
      ignoreDefaultArgs: sameWindowTabs ? ["--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"] : [],
      args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required", ...(!sameWindowTabs ? ["--disable-background-timer-throttling", "--disable-renderer-backgrounding"] : [])],
    });
    const tabContext = sameWindowTabs ? await browser.newContext({ viewport: { width: 1280, height: 720 } }) : null;
    if (tabContext) await tabContext.addInitScript(() => {
      // Reproduce browsers suspending animation frames in hidden tabs, even
      // when Chromium's WebRTC exemptions would otherwise keep them running.
      const request = window.requestAnimationFrame.bind(window);
      const nativeHidden = Object.getOwnPropertyDescriptor(Document.prototype, "hidden").get;
      Object.defineProperty(document, "hidden", { get: () => typeof window.testHidden === "boolean" ? window.testHidden : nativeHidden.call(document) });
      const pending = new Map();
      let nextId = 0;
      const schedule = id => request(time => {
        if (!pending.has(id) || (window.pauseHiddenFrames && document.hidden)) return;
        const callback = pending.get(id);
        pending.delete(id);
        callback(time);
      });
      window.requestAnimationFrame = callback => {
        const id = ++nextId;
        pending.set(id, callback);
        schedule(id);
        return id;
      };
      window.cancelAnimationFrame = id => pending.delete(id);
      document.addEventListener("visibilitychange", () => {
        if (!document.hidden) for (const id of pending.keys()) schedule(id);
      });
    });
    const errors = [];
    const url = `http://127.0.0.1:${files.address().port}/index.html`;
    async function activate(tab) {
      if (tabContext) {
        for (const other of tabContext.pages()) await other.evaluate(hidden => {
          window.testHidden = hidden;
          document.dispatchEvent(new Event("visibilitychange"));
        }, other !== tab);
      }
      await tab.bringToFront();
    }
    async function page(query) {
      let tab;
      if (tabContext && tabContext.pages().length) {
        const opened = tabContext.waitForEvent("page");
        await tabContext.pages()[0].evaluate(() => { window.open("about:blank", "_blank"); });
        tab = await opened;
      } else tab = tabContext ? await tabContext.newPage() : await browser.newPage({ viewport: { width: 1280, height: 720 } });
      if (process.env.BROWSER_SIGNALING_URL) await tab.addInitScript(value => { window.MULTI_GRAPPLER_SIGNALING_URL = value; }, process.env.BROWSER_SIGNALING_URL);
      tab.on("console", msg => {
        if (msg.type() === "error" && !msg.text().includes("favicon")) errors.push(`${query}: ${msg.text()}`);
      });
      tab.on("pageerror", error => errors.push(error.message));
      await activate(tab);
      await tab.goto(url + query);
      await activate(tab);
      return tab;
    }
    async function state(tab) { return tab.evaluate(() => window.multiplayerState); }
    async function waitOn(tab, predicate, argument) {
      if (sameWindowTabs) await activate(tab);
      try {
        await tab.waitForFunction(predicate, argument, { timeout: 30000, polling: 100 });
      } catch (error) {
        console.error("Browser state at timeout:", await state(tab));
        throw error;
      }
    }
    async function waitPlayers(tab, count) {
      await waitOn(tab, count => window.multiplayerState && !window.multiplayerState.loading && Object.keys(window.multiplayerState.players).length === count, count);
      const value = await state(tab);
      assert.equal(value.error, "");
      assert.equal(Object.values(value.players).filter(p => p.local && p.camera).length, 1);
      assert.equal(value.room_card_fits, true);
      assert.equal(value.room_card_text, value.room);
      assert.equal(value.loading_seen, true);
      assert.equal(value.background_polling, true);
      assert.equal(Object.values(value.players).every(p => p.name_upright && p.name_above), true);
    }
    async function waitGroup(tabs, count) {
      if (sameWindowTabs) {
        for (const tab of tabs) await waitPlayers(tab, count);
      } else await Promise.all(tabs.map(tab => waitPlayers(tab, count)));
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
    await waitPlayers(guest, 2);
    await waitGroup([host, guest], 2);
    if (sameWindowTabs) {
      await host.evaluate(() => { window.pauseHiddenFrames = true; });
      await guest.evaluate(() => { window.pauseHiddenFrames = true; });
    }
    const third = await page(`?role=guest&room=${room}`);
    if (sameWindowTabs) assert.equal(await host.evaluate(() => document.hidden), true);
    // The third player must join BEFORE we bring the suspended host forward.
    await waitPlayers(third, 3);
    if (sameWindowTabs) await third.evaluate(() => { window.pauseHiddenFrames = true; });
    await waitGroup([host, guest, third], 3);
    if (process.env.BROWSER_GAME_SCREENSHOT) await host.screenshot({ path: process.env.BROWSER_GAME_SCREENSHOT });
    console.log("PASS: three browsers connect through WebRTC, receive the host's level and own one camera each");
    const guestState = await state(guest);
    const guestId = Object.keys(guestState.players).find(id => guestState.players[id].local);
    const start = guestState.players[guestId].x;
    await activate(guest);
    await guest.locator("canvas").focus();
    await guest.keyboard.down("d");
    await guest.waitForFunction(({ id, start }) => window.multiplayerState.players[id].x > start + 80, { id: guestId, start });
    await guest.keyboard.up("d");
    if (sameWindowTabs) await guest.waitForTimeout(150);
    for (const tab of [host, third]) await waitOn(tab, ({ id, start }) => window.multiplayerState.players[id].x > start + 60, { id: guestId, start });
    console.log("PASS: guest movement reaches the host and another guest via MultiplayerSynchronizer");
    await activate(guest);
    await guest.mouse.move(640, 650);
    await guest.keyboard.down("Space");
    await guest.waitForFunction(id => window.multiplayerState.players[id].grapple, guestId);
    for (const tab of [host, third]) await waitOn(tab, id => window.multiplayerState.players[id].grapple, guestId);
    await activate(guest);
    await guest.keyboard.up("Space");
    console.log("PASS: guest grapple state reaches the host and another guest");
    await guest.evaluate(() => { window.multiplayerCommand = "respawn"; });
    await waitOn(guest, ({ id, start }) => Math.abs(window.multiplayerState.players[id].x - start) < 40, { id: guestId, start });
    // Let the next 30 Hz snapshot leave before suspending this guest's frames.
    if (sameWindowTabs) await guest.waitForTimeout(150);
    await waitOn(host, ({ id, start }) => Math.abs(window.multiplayerState.players[id].x - start) < 40, { id: guestId, start });
    console.log("PASS: respawn preserves the player and replicates its new position");
    const hostStart = (await state(host)).players["1"].x;
    await activate(host);
    await host.locator("canvas").focus();
    await host.keyboard.down("d");
    await host.waitForFunction(start => window.multiplayerState.players["1"].x > start + 80, hostStart);
    await host.keyboard.up("d");
    await waitOn(guest, start => window.multiplayerState.players["1"].x > start + 60, hostStart);
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
    await activate(third);
    await third.locator("canvas").focus();
    await third.keyboard.down("d");
    await third.waitForFunction(({ id, start }) => window.multiplayerState.players[id].x > start + 30, { id: thirdId, start: thirdStart });
    await third.close();
    // Verify despawning reaches a guest while the host's frame loop stays stopped.
    await waitPlayers(guest, 2);
    await waitGroup([host, guest], 2);
    console.log("PASS: closing a guest removes its replicated player");
    if (process.env.HOST_EXIT_MODE === "menu") {
      await host.evaluate(() => { window.multiplayerCommand = "leave"; });
    } else await host.close();
    await guest.waitForFunction(() => window.multiplayerState && window.multiplayerState.error.includes("host"), null, { timeout: 30000 });
    assert.equal(Object.keys((await state(guest)).players).length, 0);
    assert.equal((await state(guest)).background_polling, false);
    if (signaling) assert.equal(signaling.rooms.size, 0);
    assert.deepEqual(errors, []);
    console.log("PASS: closing the host ends the session and destroys the room; no browser/Godot errors");
  } finally {
    if (browser) await browser.close();
    if (signaling) await signaling.close();
    await new Promise(resolve => files.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
