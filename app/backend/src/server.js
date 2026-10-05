// =====================================================================
// orders-backend — Node.js API for the Task 6 multi-tier app
// Talks to Key Vault, Storage and SQL using a MANAGED IDENTITY
// (no passwords or keys anywhere in code or app settings).
// =====================================================================

// Application Insights must start first so it auto-collects
// requests, dependencies (SQL, HTTP) and exceptions.
const appInsights = require("applicationinsights");
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights.setup().setAutoCollectConsole(true, true).start();
}

const express = require("express");
const { DefaultAzureCredential } = require("@azure/identity");
const { SecretClient } = require("@azure/keyvault-secrets");
const { BlobServiceClient } = require("@azure/storage-blob");
const sql = require("mssql");

// ---------- Settings (all come from App Service app settings) ----------
const PORT = process.env.PORT || 3000;
const REGION = process.env.APP_REGION || "local";          // e.g. centralindia
const SLOT = process.env.APP_SLOT || "local";              // "production" or "staging" (slot-sticky)
const VERSION = process.env.APP_VERSION || "1.0.0";        // set by the pipeline on deploy
const KEY_VAULT_URI = process.env.KEY_VAULT_URI;            // https://kv-xxx.vault.azure.net/
const STORAGE_ACCOUNT_URL = process.env.STORAGE_ACCOUNT_URL; // https://stxxx.blob.core.windows.net
const STORAGE_CONTAINER = process.env.STORAGE_CONTAINER || "documents";
const SQL_SERVER = process.env.SQL_SERVER;                  // sql-xxx.database.windows.net
const SQL_DATABASE = process.env.SQL_DATABASE;
// AZURE_CLIENT_ID = client ID of the user-assigned managed identity
const MI_CLIENT_ID = process.env.AZURE_CLIENT_ID;

// Rollback demo switch: FAIL_HEALTH=true simulates a bad release.
// The availability test then fails -> automatic rollback.
const FAIL_HEALTH = (process.env.FAIL_HEALTH || "false").toLowerCase() === "true";

const credential = new DefaultAzureCredential(
  MI_CLIENT_ID ? { managedIdentityClientId: MI_CLIENT_ID } : {}
);

// ---------- Lazy clients (created on first use) ----------
let secretClient, blobService, sqlPool;

function getSecretClient() {
  if (!KEY_VAULT_URI) throw new Error("KEY_VAULT_URI not configured");
  secretClient ??= new SecretClient(KEY_VAULT_URI, credential);
  return secretClient;
}

function getBlobService() {
  if (!STORAGE_ACCOUNT_URL) throw new Error("STORAGE_ACCOUNT_URL not configured");
  blobService ??= new BlobServiceClient(STORAGE_ACCOUNT_URL, credential);
  return blobService;
}

async function getSqlPool() {
  if (!SQL_SERVER || !SQL_DATABASE) throw new Error("SQL_SERVER / SQL_DATABASE not configured");
  if (!sqlPool) {
    sqlPool = await new sql.ConnectionPool({
      server: SQL_SERVER,
      database: SQL_DATABASE,
      // Entra ID (Azure AD) auth via managed identity — no SQL password
      authentication: {
        type: "azure-active-directory-default",
        options: MI_CLIENT_ID ? { clientId: MI_CLIENT_ID } : {},
      },
      options: { encrypt: true },
      pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
    }).connect();
  }
  return sqlPool;
}

// ---------- App ----------
const app = express();
app.use(express.json());

// Every response says which region + slot served it.
// This is how you SEE the Traffic Manager split and the blue/green swap.
app.use((req, res, next) => {
  res.set("X-App-Region", REGION);
  res.set("X-App-Slot", SLOT);
  res.set("X-App-Version", VERSION);
  next();
});

// Health: App Service health check, Traffic Manager probe, App Insights availability test
app.get("/api/health", (req, res) => {
  if (FAIL_HEALTH) {
    return res.status(500).json({ status: "unhealthy", reason: "FAIL_HEALTH=true", region: REGION, slot: SLOT, version: VERSION });
  }
  res.json({ status: "healthy", region: REGION, slot: SLOT, version: VERSION });
});

// Who am I? (used by the frontend and the traffic-split demo)
app.get("/api/info", (req, res) => {
  res.json({
    service: "orders-backend",
    region: REGION,
    slot: SLOT,
    version: VERSION,
    hostname: process.env.WEBSITE_HOSTNAME || "localhost",
    time: new Date().toISOString(),
  });
});

// Orders from Azure SQL (managed identity, db_datareader only)
app.get("/api/orders", async (req, res, next) => {
  try {
    const pool = await getSqlPool();
    const result = await pool.request().query(
      "SELECT TOP 20 id, customer, amount, created_at FROM dbo.orders ORDER BY id DESC"
    );
    res.json({ region: REGION, count: result.recordset.length, orders: result.recordset });
  } catch (err) {
    next(err);
  }
});

// A secret from Key Vault (managed identity, "Key Vault Secrets User" role)
// Only proves access works — never return real secret values in a real API.
app.get("/api/config", async (req, res, next) => {
  try {
    const secret = await getSecretClient().getSecret("app-message");
    res.json({ source: "key-vault", name: secret.name, value: secret.value });
  } catch (err) {
    next(err);
  }
});

// Blobs from Storage (managed identity, "Storage Blob Data Reader" role)
app.get("/api/files", async (req, res, next) => {
  try {
    const container = getBlobService().getContainerClient(STORAGE_CONTAINER);
    const files = [];
    for await (const blob of container.listBlobsFlat()) {
      files.push({ name: blob.name, size: blob.properties.contentLength });
      if (files.length >= 20) break;
    }
    res.json({ container: STORAGE_CONTAINER, count: files.length, files });
  } catch (err) {
    next(err);
  }
});

// ---------- Demo endpoints for autoscale + Grafana ----------

// Burns CPU for ?ms= milliseconds -> drives the CPU autoscale rule
app.get("/api/load", (req, res) => {
  const ms = Math.min(parseInt(req.query.ms, 10) || 200, 5000);
  const end = Date.now() + ms;
  let x = 0;
  while (Date.now() < end) x += Math.sqrt(Math.random());
  res.json({ burnedMs: ms, region: REGION });
});

// Adds latency -> shows up in the p50/p95 panels
app.get("/api/slow", async (req, res) => {
  const ms = Math.min(parseInt(req.query.ms, 10) || 1000, 10000);
  await new Promise((r) => setTimeout(r, ms));
  res.json({ delayedMs: ms, region: REGION });
});

// Returns HTTP 500 -> shows up in the error-rate panel
app.get("/api/error", (req, res) => {
  res.status(500).json({ error: "Intentional error for dashboard testing", region: REGION });
});

// ---------- Error handler ----------
app.use((err, req, res, next) => {
  console.error(`[${req.method} ${req.path}]`, err.message);
  res.status(502).json({ error: err.message, region: REGION });
});

app.listen(PORT, () => {
  console.log(`orders-backend v${VERSION} listening on ${PORT} (region=${REGION}, slot=${SLOT})`);
});