#!/usr/bin/env node
/**
 * Live Verification CLI for WUMIND Cloudflare Gateway (runs against YOUR real deployed Worker & keys).
 *
 * Usage:
 *   WUMIND_GATEWAY_URL="https://wumind-gateway.<your-subdomain>.workers.dev" \
 *   WUMIND_ADMIN_SECRET="<your-admin-secret>" \
 *   node Services/WuMindGateway/scripts/live-verify-media-and-catalog.mjs [--probe] [--run-image-edit <path.png>] [--run-video]
 *
 * Never commits secrets; prints sanitized verification tables and saves real generated media locally if requested.
 */
import fs from "node:fs";
import path from "node:path";

const baseURL = (process.env.WUMIND_GATEWAY_URL || "").trim().replace(/\/+$/, "");
const adminSecret = (process.env.WUMIND_ADMIN_SECRET || "").trim();
const userToken = (process.env.WUMIND_USER_TOKEN || "").trim();
const args = process.argv.slice(2);

if (!baseURL || !adminSecret) {
  console.error("Missing WUMIND_GATEWAY_URL or WUMIND_ADMIN_SECRET environment variables.");
  process.exit(1);
}

async function api(method, route, body = null, headers = {}) {
  const res = await fetch(`${baseURL}${route}`, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, data: json };
}

const adminHdr = { "X-WuMind-Admin-Secret": adminSecret };

console.log(`==> 1. Syncing live upstream model catalogs on ${baseURL}...`);
const discover = await api("POST", "/v1/admin/models/discover", {}, adminHdr);
if (discover.status !== 200) {
  console.error("Discover failed:", discover.status, discover.data);
  process.exit(1);
}
console.table(discover.data.providerReports || []);
console.log(`Total discovered: ${discover.data.totalDiscovered}, auto-deprecated: ${discover.data.totalDeprecated}`);

const catalog = await api("GET", "/v1/admin/models/catalog", null, adminHdr);
const models = catalog.data?.models || [];
const byCap = { chat: 0, text_to_image: 0, image_edit: 0, video: 0 };
for (const m of models) {
  for (const c of m.capabilities || []) {
    if (byCap[c] !== undefined) byCap[c]++;
  }
}
console.log("Capability breakdown in candidate catalog:", byCap);

if (args.includes("--probe")) {
  // Select representative candidates across chat, image, image_edit, and video
  const picks = [];
  for (const cap of ["chat", "image_edit", "text_to_image", "video"]) {
    const candidates = models.filter((m) => !m.deprecated && (m.capabilities || []).includes(cap)).slice(0, 3);
    for (const c of candidates) {
      if (!picks.includes(c.id)) picks.push(c.id);
    }
  }
  console.log(`\n==> 2. Probing ${picks.length} representative models across capabilities:`, picks);
  const probe = await api("POST", "/v1/admin/models/probe", { modelIDs: picks }, adminHdr);
  console.table((probe.data?.results || []).map((r) => ({
    id: r.id,
    vendor: r.vendor,
    capabilities: (r.capabilities || []).join(","),
    probeStatus: r.probeStatus,
    latencyMs: r.probeLatencyMs,
    message: String(r.probeMessage || "").slice(0, 72),
  })));
}

const editIdx = args.indexOf("--run-image-edit");
if (editIdx !== -1 && args[editIdx + 1]) {
  if (!userToken) {
    console.error("Set WUMIND_USER_TOKEN (wm_live_...) to run live user image-edit / video tests.");
    process.exit(1);
  }
  const refPath = args[editIdx + 1];
  const imgB64 = fs.readFileSync(refPath).toString("base64");
  const editModels = (await api("GET", "/v1/public/models?capability=image_edit")).data?.models || [];
  if (!editModels.length) {
    console.error("No enabled & verified image_edit models found in /v1/public/models?capability=image_edit.");
    process.exit(1);
  }
  const chosen = editModels[0];
  console.log(`\n==> 3. Running live reference-image edit on ${chosen.id}...`);
  const res = await api("POST", "/v1/images/edits", {
    model: chosen.id,
    prompt: "保留原图主体构图，将整体光影调整为柔和暖阳电影质感。",
    size: "1024x1024",
    quality: "medium",
    outputFormat: "png",
    referenceImage: { base64Data: imgB64, mimeType: "image/png", filename: path.basename(refPath) },
  }, { Authorization: `Bearer ${userToken}`, "Idempotency-Key": `live-edit-${Date.now()}` });
  console.log("Image edit HTTP", res.status, res.data?.billing || res.data);
  if (res.status === 200 && res.data?.data?.[0]?.b64_json) {
    const outFile = path.resolve("live_reference_edit_output.png");
    fs.writeFileSync(outFile, Buffer.from(res.data.data[0].b64_json, "base64"));
    console.log("Saved real reference-image edit output to:", outFile);
  }
}

if (args.includes("--run-video")) {
  if (!userToken) {
    console.error("Set WUMIND_USER_TOKEN (wm_live_...) to run live video generation test.");
    process.exit(1);
  }
  const vidModels = (await api("GET", "/v1/public/models?capability=video")).data?.models || [];
  const sora = vidModels.find((m) => m.id === "sora-2") || vidModels[0];
  if (!sora) {
    console.error("No enabled & verified video models found in /v1/public/models?capability=video.");
    process.exit(1);
  }
  console.log(`\n==> 4. Submitting live 4s 720p video job on ${sora.id}...`);
  const created = await api("POST", "/v1/videos", {
    model: sora.id,
    prompt: "A calm rain-slicked futuristic Tokyo alley at night with warm neon reflections, smooth cinematic dolly shot.",
    seconds: "4",
    size: "1280x720",
  }, { Authorization: `Bearer ${userToken}`, "Idempotency-Key": `live-video-${Date.now()}` });
  console.log("Submit response:", created.status, created.data);
  if (created.status !== 200) process.exit(1);

  const jobID = created.data.id;
  for (let i = 0; i < 60; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const st = await api("GET", `/v1/videos/${encodeURIComponent(jobID)}`, null, { Authorization: `Bearer ${userToken}` });
    console.log(`[poll ${i + 1}] status=${st.data?.status} progress=${st.data?.progress}%`, st.data?.error || "");
    if (st.data?.status === "completed") {
      const mp4Res = await fetch(`${baseURL}/v1/videos/${encodeURIComponent(jobID)}/content`, {
        headers: { Authorization: `Bearer ${userToken}` },
      });
      if (!mp4Res.ok) {
        console.error("MP4 download failed:", mp4Res.status, await mp4Res.text());
        process.exit(1);
      }
      const outPath = path.resolve(`live_${sora.id}_${jobID}.mp4`);
      fs.writeFileSync(outPath, Buffer.from(await mp4Res.arrayBuffer()));
      console.log("Saved real MP4 video to:", outPath, "billing:", st.data.billing);
      break;
    }
    if (st.data?.status === "failed") {
      console.error("Video job failed on upstream (reservation released):", st.data.error);
      process.exit(1);
    }
  }
}
