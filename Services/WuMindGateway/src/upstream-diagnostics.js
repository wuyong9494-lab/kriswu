// Upstream errors can echo the credential they rejected. Redact before clipping for display or storage.
export function redactUpstreamDiagnostic(value, activeKey, extraHeaders = {}) {
  let text = String(value ?? "");
  for (const credential of [activeKey, ...Object.values(extraHeaders)]) {
    if (typeof credential === "string" && credential.trim()) {
      text = text.replaceAll(credential.trim(), "[redacted]");
    }
  }
  return text.replace(/sk-[A-Za-z0-9_-]{8,}/g, "sk-***");
}
