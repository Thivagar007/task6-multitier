import { useEffect, useState } from "react";
import { authEnabled, getAccount, signIn, signOut } from "./auth.js";
import { callApi } from "./api.js";

const ACTIONS = [
  { label: "Backend info", path: "/api/info", hint: "Which region + slot answered" },
  { label: "Orders (SQL)", path: "/api/orders", hint: "Managed identity → Azure SQL" },
  { label: "Config (Key Vault)", path: "/api/config", hint: "Managed identity → Key Vault" },
  { label: "Files (Storage)", path: "/api/files", hint: "Managed identity → Blob Storage" },
  { label: "Health", path: "/api/health", hint: "Used by availability tests" },
];

export default function App() {
  const [account, setAccount] = useState(null);
  const [result, setResult] = useState(null);
  const [busy, setBusy] = useState(false);
  const [split, setSplit] = useState(null);

  useEffect(() => {
    getAccount().then(setAccount);
  }, []);

  async function run(path) {
    setBusy(true);
    try {
      setResult({ path, ...(await callApi(path)) });
    } catch (e) {
      setResult({ path, status: "ERR", ms: 0, body: { error: e.message } });
    } finally {
      setBusy(false);
    }
  }

  // Calls /api/info 20 times and counts answers per region/slot.
  // Used for the "live traffic split" screenshot.
  async function trafficSplit() {
    setBusy(true);
    const counts = {};
    try {
      for (let i = 0; i < 20; i++) {
        const r = await callApi(`/api/info?n=${i}&t=${Date.now()}`);
        const key = r.status === 200 ? `${r.body.region} / ${r.body.slot} / v${r.body.version}` : `HTTP ${r.status}`;
        counts[key] = (counts[key] || 0) + 1;
        setSplit({ ...counts });
      }
    } catch (e) {
      setSplit({ error: e.message });
    } finally {
      setBusy(false);
    }
  }

  const needsLogin = authEnabled && !account;

  return (
    <div className="page">
      <header>
        <div>
          <h1>Orders Portal</h1>
          <p className="sub">React → Front Door → APIM (OAuth 2.0) → Traffic Manager → Node.js API</p>
        </div>
        <div className="auth">
          {!authEnabled && <span className="pill">local mode · no login</span>}
          {authEnabled && account && (
            <>
              <span className="pill">{account.username}</span>
              <button className="ghost" onClick={() => signOut().then(() => setAccount(null))}>Sign out</button>
            </>
          )}
          {needsLogin && <button onClick={() => signIn().then(setAccount)}>Sign in with Microsoft</button>}
        </div>
      </header>

      <section className="grid">
        {ACTIONS.map((a) => (
          <button key={a.path} className="card" disabled={busy || needsLogin} onClick={() => run(a.path)}>
            <strong>{a.label}</strong>
            <span>{a.hint}</span>
          </button>
        ))}
        <button className="card accent" disabled={busy || needsLogin} onClick={trafficSplit}>
          <strong>Traffic split test</strong>
          <span>20 calls, counted per region</span>
        </button>
      </section>

      {result && (
        <section className="panel">
          <div className="panel-head">
            <code>GET {result.path}</code>
            <span className={`status s${String(result.status)[0]}`}>{result.status}</span>
            <span className="muted">{result.ms} ms</span>
          </div>
          <pre>{JSON.stringify(result.body, null, 2)}</pre>
        </section>
      )}

      {split && (
        <section className="panel">
          <div className="panel-head"><strong>Traffic split</strong></div>
          {Object.entries(split).map(([k, v]) => (
            <div key={k} className="bar-row">
              <span className="bar-label">{k}</span>
              <span className="bar" style={{ width: `${(Number(v) / 20) * 100}%` }} />
              <span className="bar-count">{v}</span>
            </div>
          ))}
        </section>
      )}

      <footer className="muted">Frontend build {import.meta.env.MODE} · {new Date().getFullYear()}</footer>
    </div>
  );
}