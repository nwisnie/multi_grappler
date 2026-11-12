export class RequestError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

export async function boundedBytes(stream, maximum) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximum) throw new RequestError("The request data is too large.", 413);
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

export async function readJson(request, maximum) {
  if (request.headers.get("Content-Type")?.split(";")[0].trim().toLowerCase() !== "application/json") throw new RequestError("Use application/json.", 415);
  if (Number(request.headers.get("Content-Length")) > maximum) throw new RequestError("The request data is too large.", 413);
  let body;
  try { body = JSON.parse(new TextDecoder().decode(await boundedBytes(request.body, maximum))); }
  catch (error) { if (error instanceof RequestError) throw error; throw new RequestError("Invalid JSON."); }
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new RequestError("Invalid request.");
  return body;
}

export function requireSecureTransport(request) {
  const url = new URL(request.url);
  if (url.protocol !== "https:" && !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)) {
    throw new RequestError("Account requests require HTTPS.", 400);
  }
}
