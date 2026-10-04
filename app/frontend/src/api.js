import { getToken } from "./auth.js";

// Local: "" -> relative /api/... (Vite proxy). Azure: the APIM API URL.
const BASE = (import.meta.env.VITE_API_BASE_URL || "").replace(/\/$/, "");

export async function callApi(path) {
  const token = await getToken();
  const started = performance.now();
  const res = await fetch(`${BASE}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  const ms = Math.round(performance.now() - started);
  let body;
  try {
    body = await res.json();
  } catch {
    body = { raw: await res.text() };
  }
  return { status: res.status, ms, body };
}