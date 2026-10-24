// Dependency-free Chrome DevTools smoke test for an exported Web build.
// Run: node tests/web_smoke.mjs (Chrome must be installed).
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';

const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webRoot = path.join(workspace, 'build', 'web');
const screenshots = path.join(workspace, 'build', 'screenshots');
await mkdir(screenshots, { recursive: true });
const profile = await mkdtemp(path.join(workspace, 'build', 'chrome-smoke-'));
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml' };
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const target = path.resolve(webRoot, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!target.startsWith(webRoot + path.sep)) throw new Error('Invalid path');
    const bytes = await readFile(target);
    response.writeHead(200, { 'Content-Type': mime[path.extname(target)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
    response.end(bytes);
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/index.html`;
const chromePath = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const chrome = spawn(chromePath, ['--headless=new', '--remote-debugging-pipe', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--window-size=1280,720', 'about:blank'], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
const pending = new Map();
let sequence = 0;
let buffer = '';
let session;
const errors = [];
chrome.stderr.on('data', () => {});
chrome.on('error', error => {
  for (const request of pending.values()) request.reject(error);
});
chrome.stdio[4].on('data', bytes => {
  buffer += bytes.toString();
  let end;
  while ((end = buffer.indexOf('\0')) !== -1) {
    const message = JSON.parse(buffer.slice(0, end));
    buffer = buffer.slice(end + 1);
    if (message.id) {
      const request = pending.get(message.id);
      if (request) {
        clearTimeout(request.timeout);
        pending.delete(message.id);
        message.error ? request.reject(new Error(JSON.stringify(message.error))) : request.resolve(message.result);
      }
    } else if (message.method === 'Runtime.exceptionThrown') {
      errors.push(JSON.stringify(message.params.exceptionDetails));
    } else if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') {
      errors.push(message.params.args.map(argument => argument.value || argument.description).join(' '));
    }
  }
});
function send(method, params = {}, sessionId) {
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 30000);
    pending.set(id, { resolve, reject, timeout });
    chrome.stdio[3].write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + '\0');
  });
}
const page = (method, params = {}) => send(method, params, session);
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function click(x, y) {
  await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await page('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await page('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  await pause(120);
}
async function screenshot(name, delay = 250) {
  await pause(delay);
  const result = await page('Page.captureScreenshot', { format: 'png' });
  await writeFile(path.join(screenshots, name + '.png'), Buffer.from(result.data, 'base64'));
  console.log('SCREENSHOT ' + name);
}

async function shortcut(key, code, virtualKey, modifiers = 0) {
  await page('Input.dispatchKeyEvent', { type: 'keyDown', key, code, windowsVirtualKeyCode: virtualKey, modifiers });
  await page('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: virtualKey, modifiers });
  await pause(200);
}

try {
  await send('Browser.getVersion');
  await send('Browser.grantPermissions', { origin: new URL(url).origin, permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] });
  const target = await send('Target.createTarget', { url: 'about:blank' });
  session = (await send('Target.attachToTarget', { targetId: target.targetId, flatten: true })).sessionId;
  await page('Page.enable');
  await page('Runtime.enable');
  await page('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await page('Page.navigate', { url });
  for (let attempt = 0; attempt < 120; attempt++) {
    await pause(250);
    const state = await page('Runtime.evaluate', { expression: "document.getElementById('status') === null", returnByValue: true });
    if (state.result.value) break;
    if (attempt === 119) throw new Error('Web build did not finish loading');
  }
  await pause(800);
  await screenshot('web-demo');
  await click(1190, 32);
  await screenshot('web-editor-empty');
  for (let step = 0; step < 8; step++) {
    await page('Input.dispatchMouseEvent', { type: 'mousePressed', x: 1100, y: 400, button: 'right', buttons: 2, clickCount: 1 });
    await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 200, y: 400, button: 'right', buttons: 2 });
    await page('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 200, y: 400, button: 'right', clickCount: 1 });
  }
  await screenshot('web-editor-distant-background');
  await click(444, 37); // Show whole level restores the fitted camera.
  if (errors.length) throw new Error(errors.join('\n'));
  // Visual checks for the slanted hit areas and passive build caption.
  await click(206, 86); // Select.
  await click(345, 74); // Painted overhang of Line beside the Curve boundary.
  await screenshot('web-toolbar-angle-click');
  await click(382, 86); // Curve.
  await click(344, 86); // Separator gap.
  await click(60, 86); // Passive Build Options caption.
  await screenshot('web-toolbar-gap-caption');
  await click(310, 86); // Line.
  await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 1100, y: 400 });
  await pause(250);
  await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 382, y: 86 });
  await pause(45);
  await screenshot('web-toolbar-hover-mid', 0);
  await screenshot('web-toolbar-hover-on');
  await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 1100, y: 400 });
  await pause(70);
  await screenshot('web-toolbar-exit-mid', 0);
  await screenshot('web-toolbar-exit-off');
  // Place on the fitted board, leaving space above the terrain for a spawn.
  await click(450, 450);
  await click(750, 450);
  await click(382, 86); // Curve.
  await click(750, 450);
  await click(800, 350);
  await click(820, 420);
  await click(458, 86); // Spawn.
  await click(550, 400);
  await click(558, 86); // Orb.
  await click(650, 350);
  await screenshot('web-editor-drawing');
  await click(830, 37); // Export.
  await screenshot('web-export');
  await shortcut('c', 'KeyC', 67, 2); // Manual Ctrl+C fallback.
  const copied = await page('Runtime.evaluate', { expression: 'navigator.clipboard.readText()', awaitPromise: true, returnByValue: true });
  const code = copied.result.value;
  if (!code?.startsWith('MG1-')) throw new Error('Exported level code was not copied');
  const payload = inflateSync(Buffer.from(code.slice(4), 'base64'));
  if (payload.readUInt16LE(1) !== 2 || payload[3] !== 1 || payload[4] === 255) throw new Error('Browser placements did not serialize as expected');
  console.log(`BROWSER CODE: ${code.length} characters, 2 segments, 1 orb, and spawn`);
  await page('Runtime.evaluate', { expression: "navigator.clipboard.writeText('')", awaitPromise: true });
  await click(430, 570); // Copy button.
  const buttonCopy = await page('Runtime.evaluate', { expression: 'navigator.clipboard.readText()', awaitPromise: true, returnByValue: true });
  if (buttonCopy.result.value !== code) throw new Error('Copy button changed the code');
  await click(660, 570); // Done.
  await click(718, 37); // Clear.
  await screenshot('web-clear-dialog');
  await shortcut('Enter', 'Enter', 13);
  await click(954, 37); // Import.
  await click(400, 220);
  await shortcut('v', 'KeyV', 86, 2);
  await screenshot('web-import');
  await click(500, 570); // Replace draft.
  await click(830, 37); // Export again to verify exact round trip.
  await shortcut('c', 'KeyC', 67, 2);
  const roundTrip = await page('Runtime.evaluate', { expression: 'navigator.clipboard.readText()', awaitPromise: true, returnByValue: true });
  if (roundTrip.result.value !== code) throw new Error('Browser import/export round trip changed the level');
  await click(660, 570);
  for (let step = 0; step < 7; step++) {
    await page('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 650, y: 400, deltaX: 0, deltaY: -120 });
    await pause(30);
  }
  await screenshot('web-editor-zoom');
  await click(206, 86); // Select / move exposes the draggable handles.
  await page('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 650, y: 579 });
  await screenshot('web-editor-hover');
  await click(186, 37); // Playtest.
  await pause(700);
  await screenshot('web-playtest');
  await click(1190, 32); // Back to editor.
  await screenshot('web-editor-return');
  await click(186, 37);
  await click(1090, 32); // Restart.
  await click(1190, 32);
  await screenshot('web-editor-return-second');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('WEB SMOKE: drawing, clipboard, import/export, zoom, playtest, restart, and editor return completed without runtime errors');
} finally {
  await send('Browser.close').catch(() => {});
  chrome.kill();
  server.close();
}
