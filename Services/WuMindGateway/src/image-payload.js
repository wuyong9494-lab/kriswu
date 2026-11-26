/**
 * Shared WUMIND Image Binary Validator & Multi-Protocol Response Extractor.
 * Used identically by BOTH catalog probing (`model-catalog.js`) AND runtime managed generation (`media-routes.js`).
 * Guarantees that HTTP 200 alone NEVER counts as image success — only real, decodable, displayable PNG/JPEG/WebP bytes pass!
 */

const MAX_IMAGE_BYTES = 16 * 1024 * 1024;
const MAX_DIMENSION = 8192;

export function encodeUint8ArrayBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

export function decodeBase64BytesStrict(rawB64) {
  if (typeof rawB64 !== "string") return null;
  const clean = rawB64.replace(/^data:[^;]+;base64,/i, "").replace(/\s+/g, "");
  if (!clean || clean.length % 4 === 1) return null;
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(clean)) return null;
  try {
    const bin = atob(clean);
    if (bin.length === 0) return null;
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return { bytes: out, cleanBase64: clean };
  } catch {
    return null;
  }
}

function readBE32(bytes, idx) {
  return ((bytes[idx] << 24) >>> 0) | (bytes[idx + 1] << 16) | (bytes[idx + 2] << 8) | bytes[idx + 3];
}

/**
 * Inspects decoded binary bytes to verify a complete, displayable PNG, JPEG, or WebP raster image
 * with valid non-zero dimensions (`1..8192`). Rejects text, JSON, truncated files, and corrupt blobs.
 */
export function inspectDisplayableImageBytes(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 12 || bytes.length > MAX_IMAGE_BYTES) {
    return { valid: false, reason: "invalid_byte_length" };
  }

  // 1. PNG: 8-byte signature + IHDR chunk (length 13) + valid IEND trailer
  const pngPrefix = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52];
  const pngIEND = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82];
  if (bytes.length >= 33 && pngPrefix.every((b, idx) => bytes[idx] === b)) {
    const hasIEND = pngIEND.every((b, idx) => bytes[bytes.length - 12 + idx] === b);
    if (!hasIEND) return { valid: false, reason: "truncated_png_missing_iend" };
    const width = readBE32(bytes, 16);
    const height = readBE32(bytes, 20);
    if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
      return { valid: false, reason: "invalid_png_dimensions" };
    }
    return { valid: true, mimeType: "image/png", width, height, byteLength: bytes.length };
  }

  // 2. WebP: RIFF....WEBP + VP8X / VP8L / VP8
  if (
    bytes.length >= 30 &&
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    const riffSize = (bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)) >>> 0;
    if (riffSize + 8 > bytes.length) {
      return { valid: false, reason: "truncated_webp" };
    }
    const fourCC = String.fromCharCode(bytes[12], bytes[13], bytes[14], bytes[15]);
    let width = 0;
    let height = 0;
    if (fourCC === "VP8X") {
      width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    } else if (fourCC === "VP8L") {
      const b0 = bytes[21], b1 = bytes[22], b2 = bytes[23], b3 = bytes[24];
      width = 1 + (b0 | ((b1 & 0x3f) << 8));
      height = 1 + (((b1 & 0xc0) >> 6) | (b2 << 2) | ((b3 & 0x0f) << 10));
    } else if (fourCC === "VP8 ") {
      width = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
      height = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
    } else {
      return { valid: false, reason: "unsupported_webp_chunk" };
    }
    if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
      return { valid: false, reason: "invalid_webp_dimensions" };
    }
    return { valid: true, mimeType: "image/webp", width, height, byteLength: bytes.length };
  }

  // 3. JPEG: FF D8 SOI + SOF0..SOF15 + FF D9 EOI
  if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    if (bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) {
      return { valid: false, reason: "truncated_jpeg_missing_eoi" };
    }
    const sofMarkers = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
    let idx = 2;
    while (idx + 3 < bytes.length) {
      if (bytes[idx] !== 0xff) return { valid: false, reason: "corrupt_jpeg_marker" };
      idx += 1;
      while (idx < bytes.length && bytes[idx] === 0xff) idx += 1;
      if (idx + 2 >= bytes.length) return { valid: false, reason: "truncated_jpeg_header" };
      const marker = bytes[idx];
      if (marker === 0xda || marker === 0xd9) break;
      idx += 1;
      const segLen = (bytes[idx] << 8) | bytes[idx + 1];
      if (segLen < 2 || idx + segLen > bytes.length) return { valid: false, reason: "corrupt_jpeg_segment" };
      if (sofMarkers.has(marker)) {
        if (segLen < 8) return { valid: false, reason: "corrupt_jpeg_sof" };
        const height = (bytes[idx + 3] << 8) | bytes[idx + 4];
        const width = (bytes[idx + 5] << 8) | bytes[idx + 6];
        if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
          return { valid: false, reason: "invalid_jpeg_dimensions" };
        }
        return { valid: true, mimeType: "image/jpeg", width, height, byteLength: bytes.length };
      }
      idx += segLen;
    }
    return { valid: false, reason: "jpeg_missing_sof" };
  }

  return { valid: false, reason: "unrecognized_image_header" };
}

export function isAllowedUpstreamContentURL(rawURL, supply) {
  try {
    const parsed = new URL(String(rawURL || ""));
    if (parsed.protocol !== "https:") return false;
    if (parsed.username || parsed.password) return false;
    const host = parsed.hostname.toLowerCase();
    const baseHost = supply?.baseOrigin ? new URL(supply.baseOrigin).hostname.toLowerCase() : "";
    if (baseHost && host === baseHost) return true;
    if (
      host === "aihubmix.com" ||
      host.endsWith(".aihubmix.com") ||
      host === "api.inferera.com" ||
      host.endsWith(".inferera.com")
    ) {
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

/**
 * Extracts images from Gemini native, OpenAI standard, or AIHubMix Unified JSON responses,
 * and strictly decodes + validates EVERY image to confirm it is displayable (PNG/JPEG/WebP with valid W×H).
 */
export async function extractAndValidateGeneratedImages(parsed, { supply } = {}) {
  const candidates = [];
  const rejectedReasons = [];

  // 1. Gemini native generateContent (`candidates[].content.parts[].inlineData` or `inline_data`, skipping `thought`)
  if (Array.isArray(parsed?.candidates)) {
    for (const candidate of parsed.candidates) {
      const parts = candidate?.content?.parts || [];
      for (const part of parts) {
        if (!part || part.thought) continue;
        const inline = part.inlineData || part.inline_data;
        if (inline && typeof inline.data === "string" && inline.data.length > 0) {
          candidates.push({ kind: "b64", b64: inline.data });
        }
      }
    }
  }

  // 2. OpenAI / AIHubMix standard `data[].b64_json`
  if (candidates.length === 0 && Array.isArray(parsed?.data)) {
    for (const img of parsed.data) {
      if (typeof img?.b64_json === "string" && img.b64_json.length > 0) {
        candidates.push({ kind: "b64", b64: img.b64_json });
      }
    }
  }

  // 3. AIHubMix Unified `/ai/v1/images/generations` (`output[].b64_json` or SSRF-safe same-origin `output[].content_url`)
  if (candidates.length === 0 && Array.isArray(parsed?.output)) {
    for (const item of parsed.output) {
      if (typeof item?.b64_json === "string" && item.b64_json.length > 0) {
        candidates.push({ kind: "b64", b64: item.b64_json });
      } else if (typeof item?.content_url === "string" && item.content_url.length > 0) {
        if (!isAllowedUpstreamContentURL(item.content_url, supply)) {
          rejectedReasons.push("blocked_off_origin_content_url");
          continue;
        }
        candidates.push({ kind: "content_url", url: item.content_url });
      }
    }
  }

  const images = [];
  for (const cand of candidates) {
    if (cand.kind === "b64") {
      const decoded = decodeBase64BytesStrict(cand.b64);
      if (!decoded) {
        rejectedReasons.push("invalid_base64");
        continue;
      }
      const check = inspectDisplayableImageBytes(decoded.bytes);
      if (!check.valid) {
        rejectedReasons.push(check.reason);
        continue;
      }
      images.push({
        b64_json: decoded.cleanBase64,
        mime_type: check.mimeType,
        width: check.width,
        height: check.height,
        byteLength: check.byteLength,
      });
    } else if (cand.kind === "content_url") {
      const dl = await fetch(cand.url, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
      });
      if (!dl.ok) {
        rejectedReasons.push(`content_url_http_${dl.status}`);
        continue;
      }
      const buf = new Uint8Array(await dl.arrayBuffer());
      const check = inspectDisplayableImageBytes(buf);
      if (!check.valid) {
        rejectedReasons.push(check.reason);
        continue;
      }
      images.push({
        b64_json: encodeUint8ArrayBase64(buf),
        mime_type: check.mimeType,
        width: check.width,
        height: check.height,
        byteLength: check.byteLength,
      });
    }
  }

  return { images, rejectedReasons };
}
