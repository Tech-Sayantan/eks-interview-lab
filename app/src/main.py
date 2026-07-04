import json
import os
import socket
import time
from typing import Any

import boto3
import redis
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse


app = FastAPI(title="EKS Interview Lab App", version=os.getenv("APP_VERSION", "dev"))


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default)


def redis_client() -> redis.Redis:
    redis_host = env("REDIS_HOST", "interview-app-redis")
    redis_port = int(env("REDIS_PORT", "6379"))
    return redis.Redis(host=redis_host, port=redis_port, socket_timeout=2, decode_responses=True)


def secret_summary(secret_value: str | bytes | None) -> dict[str, Any]:
    if secret_value is None:
        return {"type": "empty", "length": 0, "keys": []}
    if isinstance(secret_value, bytes):
        return {"type": "binary", "length": len(secret_value), "keys": []}
    try:
        parsed = json.loads(secret_value)
    except json.JSONDecodeError:
        return {"type": "string", "length": len(secret_value), "keys": []}
    if isinstance(parsed, dict):
        return {"type": "json", "length": len(secret_value), "keys": sorted(parsed.keys())}
    return {"type": type(parsed).__name__, "length": len(secret_value), "keys": []}


def app_payload() -> dict[str, Any]:
    return {
        "app": "eks-interview-lab",
        "version": env("APP_VERSION", "dev"),
        "environment": env("APP_ENV", "local"),
        "message": env("APP_MESSAGE", "hello from Kubernetes"),
        "pod": {
            "name": env("POD_NAME"),
            "namespace": env("POD_NAMESPACE"),
            "node": env("NODE_NAME"),
            "ip": env("POD_IP"),
            "hostname": socket.gethostname(),
        },
        "try": [
            "/api/info",
            "/healthz",
            "/readyz",
            "/config",
            "/secret-check",
            "/secret-manager-check",
            "/redis/incr",
            "/aws/identity",
            "/burn?seconds=5",
        ],
    }


def mask_account(account: str | None) -> str:
    if not account or len(account) < 8:
        return "not available"
    return f"{account[:4]}...{account[-4:]}"


def role_name_from_arn(arn: str | None) -> str:
    if not arn:
        return "not available"
    if "assumed-role/" in arn:
        return arn.split("assumed-role/", 1)[1].split("/", 1)[0]
    if ":role/" in arn:
        return arn.split(":role/", 1)[1]
    return "not available"


@app.get("/", response_class=HTMLResponse)
def root() -> HTMLResponse:
    return HTMLResponse(
        """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>EKS Interview Lab</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #14213d;
      --muted: #64748b;
      --line: #d7dee9;
      --panel: #ffffff;
      --panel-soft: #f7f9fc;
      --blue: #1d4ed8;
      --teal: #0f766e;
      --green: #047857;
      --amber: #b7791f;
      --red: #dc2626;
      --shadow: 0 18px 44px rgba(20, 33, 61, .10);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background: #edf2f7;
    }
    .shell {
      min-height: 100vh;
      display: grid;
      grid-template-rows: auto 1fr;
    }
    header {
      background: #101820;
      color: #f8fafc;
      border-bottom: 1px solid rgba(255,255,255,.12);
    }
    .header-inner {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 30px 0 26px;
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 24px;
      align-items: end;
    }
    .hero-stats {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 18px;
    }
    .hero-stat {
      border: 1px solid rgba(255,255,255,.14);
      border-radius: 999px;
      background: rgba(255,255,255,.08);
      color: #dbeafe;
      min-height: 34px;
      display: inline-flex;
      align-items: center;
      padding: 0 12px;
      font-size: 13px;
      font-weight: 800;
    }
    .eyebrow {
      margin: 0 0 10px;
      color: #93c5fd;
      font-size: 13px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    h1 {
      margin: 0;
      font-size: clamp(32px, 5vw, 58px);
      line-height: 1;
      letter-spacing: 0;
    }
    .subtitle {
      margin: 12px 0 0;
      color: #cbd5e1;
      max-width: 760px;
      font-size: 17px;
      line-height: 1.55;
    }
    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 9px;
      min-height: 40px;
      padding: 0 14px;
      border: 1px solid rgba(255,255,255,.2);
      border-radius: 999px;
      background: rgba(255,255,255,.08);
      color: #e2e8f0;
      font-weight: 700;
      white-space: nowrap;
    }
    .dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: var(--amber);
      box-shadow: 0 0 0 5px rgba(183, 121, 31, .18);
    }
    .dot.ok {
      background: var(--green);
      box-shadow: 0 0 0 5px rgba(5, 150, 105, .18);
    }
    .dot.bad {
      background: var(--red);
      box-shadow: 0 0 0 5px rgba(220, 38, 38, .16);
    }
    main {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 24px 0 44px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(12, 1fr);
      gap: 16px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
      padding: 20px;
      min-width: 0;
    }
    .span-4 { grid-column: span 4; }
    .span-6 { grid-column: span 6; }
    .span-8 { grid-column: span 8; }
    .span-12 { grid-column: span 12; }
    h2 {
      margin: 0 0 14px;
      font-size: 18px;
      letter-spacing: 0;
    }
    .metric {
      display: grid;
      gap: 4px;
      padding: 13px 0;
      border-top: 1px solid var(--line);
    }
    .metric:first-of-type { border-top: 0; padding-top: 0; }
    .label {
      color: var(--muted);
      font-size: 12px;
      font-weight: 800;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .value {
      font-size: 16px;
      line-height: 1.35;
      overflow-wrap: anywhere;
    }
    .value.big {
      font-size: 30px;
      font-weight: 800;
    }
    .value.ok { color: var(--green); }
    .value.warn { color: var(--amber); }
    .mini {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.45;
      overflow-wrap: anywhere;
    }
    .stack {
      display: grid;
      gap: 10px;
    }
    .chip-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .chip {
      border: 1px solid var(--line);
      background: var(--panel-soft);
      border-radius: 999px;
      padding: 8px 10px;
      font-size: 13px;
      font-weight: 700;
      color: #334155;
    }
    .route-list {
      display: grid;
      gap: 8px;
    }
    .route {
      display: grid;
      grid-template-columns: 120px 1fr;
      gap: 10px;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel-soft);
      padding: 10px;
    }
    .route code {
      width: fit-content;
      background: #e8eef7;
    }
    .topology {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 8px;
      margin-top: 10px;
    }
    .node {
      min-height: 74px;
      display: grid;
      place-items: center;
      text-align: center;
      padding: 10px;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: var(--panel-soft);
      font-size: 13px;
      font-weight: 800;
      color: #1f2937;
    }
    .node.primary {
      border-color: rgba(37, 99, 235, .35);
      background: #eff6ff;
      color: #1d4ed8;
    }
    .node.aws {
      border-color: rgba(15, 118, 110, .35);
      background: #ecfdf5;
      color: #0f766e;
    }
    .button-row {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 14px;
    }
    button, a.button {
      appearance: none;
      border: 0;
      border-radius: 8px;
      background: var(--blue);
      color: white;
      min-height: 42px;
      padding: 0 14px;
      font-weight: 800;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
    }
    button.secondary, a.button.secondary {
      background: #e2e8f0;
      color: #172033;
    }
    code {
      background: #eef2f7;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 2px 6px;
      color: #1e293b;
    }
    .footer-note {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.55;
      margin-top: 16px;
    }
    @media (max-width: 880px) {
      .header-inner { grid-template-columns: 1fr; align-items: start; }
      .span-4, .span-6, .span-8 { grid-column: span 12; }
      .topology { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <div class="header-inner">
        <div>
          <p class="eyebrow">AWS EKS practice environment</p>
          <h1>EKS Interview Lab</h1>
          <p class="subtitle">A live Kubernetes deployment using Docker, Helm, ECR, ALB Ingress, Route 53, ACM, Redis StatefulSet, EBS CSI, IRSA, HPA, NetworkPolicy, and GitHub Actions OIDC.</p>
          <div class="hero-stats">
            <span class="hero-stat">ALB Ingress</span>
            <span class="hero-stat">IRSA</span>
            <span class="hero-stat">EBS gp3</span>
            <span class="hero-stat">HPA 2-5</span>
            <span class="hero-stat">Helm Release</span>
          </div>
        </div>
        <div class="status-pill"><span id="overall-dot" class="dot"></span><span id="overall-status">Checking live status</span></div>
      </div>
    </header>
    <main>
      <section class="grid">
        <article class="card span-4">
          <h2>Runtime</h2>
          <div class="metric">
            <div class="label">App Version</div>
            <div id="version" class="value big">loading</div>
          </div>
          <div class="metric">
            <div class="label">Environment</div>
            <div id="environment" class="value">loading</div>
          </div>
          <div class="metric">
            <div class="label">Message</div>
            <div id="message" class="value">loading</div>
          </div>
          <div class="metric">
            <div class="label">Current Pod</div>
            <div id="pod-name" class="value">loading</div>
            <div id="pod-node" class="mini">node loading</div>
          </div>
        </article>
        <article class="card span-4">
          <h2>Health</h2>
          <div class="metric">
            <div class="label">Liveness</div>
            <div id="healthz" class="value big">checking</div>
          </div>
          <div class="metric">
            <div class="label">Readiness</div>
            <div id="readyz" class="value">checking Redis dependency</div>
          </div>
          <div class="metric">
            <div class="label">Secret Mount</div>
            <div id="secret" class="value">checking</div>
          </div>
          <div class="metric">
            <div class="label">Secrets Manager</div>
            <div id="secret-manager" class="value">checking IRSA access</div>
          </div>
        </article>
        <article class="card span-4">
          <h2>Identity</h2>
          <div class="metric">
            <div class="label">AWS Mode</div>
            <div id="aws-mode" class="value big">IRSA</div>
          </div>
          <div class="metric">
            <div class="label">Account</div>
            <div id="aws-account" class="value">masked</div>
          </div>
          <div class="metric">
            <div class="label">Role</div>
            <div id="aws-role" class="value">loading</div>
          </div>
        </article>
        <article class="card span-8">
          <h2>Request Path</h2>
          <div class="topology">
            <div class="node aws">Route 53<br>DNS</div>
            <div class="node aws">ACM<br>TLS</div>
            <div class="node primary">ALB<br>Ingress</div>
            <div class="node">Service<br>ClusterIP</div>
            <div class="node">Deployment<br>FastAPI</div>
            <div class="node">StatefulSet<br>Redis</div>
          </div>
          <p class="footer-note">Traffic enters through the AWS Load Balancer Controller managed ALB, then reaches Kubernetes Service endpoints backed by ready app pods.</p>
        </article>
        <article class="card span-4">
          <h2>Interactive Checks</h2>
          <div class="stack">
            <div class="metric">
              <div class="label">Redis Counter</div>
              <div id="redis-counter" class="value big">not run</div>
            </div>
            <div class="button-row">
              <button id="redis-button" type="button">Run Redis Check</button>
              <a class="button secondary" href="/docs">Open API Docs</a>
            </div>
          </div>
        </article>
        <article class="card span-12">
          <h2>Live Practice Surface</h2>
          <div class="chip-row">
            <span class="chip">Deployment</span>
            <span class="chip">Service</span>
            <span class="chip">Ingress</span>
            <span class="chip">ConfigMap</span>
            <span class="chip">Secret</span>
            <span class="chip">Secrets Manager</span>
            <span class="chip">ServiceAccount</span>
            <span class="chip">IRSA</span>
            <span class="chip">StatefulSet</span>
            <span class="chip">Headless Service</span>
            <span class="chip">PVC</span>
            <span class="chip">StorageClass</span>
            <span class="chip">HPA</span>
            <span class="chip">NetworkPolicy</span>
            <span class="chip">DaemonSet</span>
            <span class="chip">ResourceQuota</span>
            <span class="chip">LimitRange</span>
            <span class="chip">PDB</span>
            <span class="chip">ECR</span>
            <span class="chip">EBS CSI</span>
            <span class="chip">GitHub Actions OIDC</span>
          </div>
          <p class="footer-note">Practice endpoints stay intentionally visible because this page doubles as a quick smoke-test dashboard for the interview lab.</p>
        </article>
        <article class="card span-6">
          <h2>Smoke Test Routes</h2>
          <div class="route-list">
            <div class="route"><code>/healthz</code><span>container liveness</span></div>
            <div class="route"><code>/readyz</code><span>readiness plus Redis dependency</span></div>
            <div class="route"><code>/secret-manager-check</code><span>IRSA access to AWS Secrets Manager</span></div>
            <div class="route"><code>/redis/incr</code><span>StatefulSet plus EBS-backed Redis check</span></div>
          </div>
        </article>
        <article class="card span-6">
          <h2>Operational Signals</h2>
          <div class="route-list">
            <div class="route"><code>Helm</code><span>release history and rollback practice</span></div>
            <div class="route"><code>HPA</code><span>CPU-based replica scaling from 2 to 5 pods</span></div>
            <div class="route"><code>PDB</code><span>planned disruption protection during drains</span></div>
            <div class="route"><code>EBS</code><span>zonal volume scheduling and attach behavior</span></div>
          </div>
        </article>
      </section>
    </main>
  </div>
  <script>
    const text = (id, value) => { document.getElementById(id).textContent = value; };
    const setOverall = (ok) => {
      const dot = document.getElementById("overall-dot");
      dot.classList.remove("ok", "bad");
      dot.classList.add(ok ? "ok" : "bad");
      text("overall-status", ok ? "Live and ready" : "Needs attention");
    };
    async function getJson(path) {
      const res = await fetch(path, { cache: "no-store" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || JSON.stringify(data));
      return data;
    }
    async function refresh() {
      let healthy = false;
      let ready = false;
      try {
        const info = await getJson("/api/info");
        text("version", info.version || "unknown");
        text("environment", info.environment || "unknown");
        text("message", info.message || "unknown");
        text("pod-name", info.pod?.name || "unknown");
        text("pod-node", `node ${info.pod?.node || "unknown"} - ip ${info.pod?.ip || "unknown"}`);
      } catch (err) {
        text("message", "Could not load app metadata");
        text("pod-name", "metadata unavailable");
        text("pod-node", "node unavailable");
      }
      try {
        await getJson("/healthz");
        healthy = true;
        text("healthz", "OK");
        document.getElementById("healthz").className = "value big ok";
      } catch (err) {
        text("healthz", "failed");
        document.getElementById("healthz").className = "value big warn";
      }
      try {
        const readiness = await getJson("/readyz");
        ready = true;
        text("readyz", `${readiness.status} - Redis ${readiness.redis}`);
      } catch (err) {
        text("readyz", "degraded - Redis check failed");
      }
      try {
        const secret = await getJson("/secret-check");
        text("secret", secret.secret_mounted ? `mounted, length ${secret.length}` : "missing");
      } catch (err) {
        text("secret", "check failed");
      }
      try {
        const managedSecret = await getJson("/secret-manager-check");
        text("secret-manager", `${managedSecret.status}, ${managedSecret.summary.type}, keys: ${managedSecret.summary.keys.join(", ") || "none"}`);
      } catch (err) {
        text("secret-manager", "check failed");
      }
      try {
        const aws = await getJson("/api/aws-summary");
        text("aws-account", aws.account);
        text("aws-role", aws.role);
        text("aws-mode", aws.mode);
      } catch (err) {
        text("aws-account", "not available");
        text("aws-role", "not available");
      }
      setOverall(healthy && ready);
    }
    document.getElementById("redis-button").addEventListener("click", async () => {
      text("redis-counter", "running");
      try {
        const data = await getJson("/redis/incr");
        text("redis-counter", String(data.counter));
      } catch (err) {
        text("redis-counter", "failed");
      }
    });
    refresh();
    setInterval(refresh, 30000);
  </script>
</body>
</html>
        """
    )


@app.get("/api/info")
def api_info() -> dict[str, Any]:
    return app_payload()


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> JSONResponse:
    try:
        redis_client().ping()
        return JSONResponse({"status": "ready", "redis": "ok"})
    except Exception as exc:
        return JSONResponse({"status": "degraded", "redis": str(exc)}, status_code=503)


@app.get("/config")
def config() -> dict[str, str]:
    return {
        "APP_ENV": env("APP_ENV"),
        "APP_MESSAGE": env("APP_MESSAGE"),
        "REDIS_HOST": env("REDIS_HOST"),
        "REDIS_PORT": env("REDIS_PORT"),
        "AWS_SECRET_ID": env("AWS_SECRET_ID"),
    }


@app.get("/secret-check")
def secret_check() -> dict[str, Any]:
    value = env("DEMO_API_KEY")
    return {
        "secret_mounted": bool(value),
        "length": len(value),
        "note": "The app never returns the secret value.",
    }


@app.get("/secret-manager-check")
def secret_manager_check() -> dict[str, Any]:
    secret_id = env("AWS_SECRET_ID", "interview/app/demo")
    try:
        response = boto3.client("secretsmanager").get_secret_value(SecretId=secret_id)
        value = response.get("SecretString")
        if value is None:
            value = response.get("SecretBinary")
        return {
            "status": "retrieved",
            "source": "AWS Secrets Manager through pod IRSA",
            "secret_id": secret_id,
            "summary": secret_summary(value),
            "note": "The app proves retrieval but never returns the secret value.",
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Secrets Manager unavailable: {exc}") from exc


@app.get("/redis/incr")
def redis_incr() -> dict[str, Any]:
    try:
        count = redis_client().incr("interview-lab-counter")
        return {"counter": int(count)}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Redis unavailable: {exc}") from exc


@app.get("/aws/identity")
def aws_identity() -> dict[str, Any]:
    try:
        sts = boto3.client("sts")
        identity = sts.get_caller_identity()
        return {
            "account": identity.get("Account"),
            "arn": identity.get("Arn"),
            "user_id": identity.get("UserId"),
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"AWS identity unavailable: {exc}") from exc


@app.get("/api/aws-summary")
def aws_summary() -> dict[str, str]:
    try:
        sts = boto3.client("sts")
        identity = sts.get_caller_identity()
        return {
            "mode": "IRSA",
            "account": mask_account(identity.get("Account")),
            "role": role_name_from_arn(identity.get("Arn")),
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"AWS summary unavailable: {exc}") from exc


@app.get("/burn")
def burn(seconds: int = Query(default=10, ge=1, le=60)) -> dict[str, Any]:
    deadline = time.time() + seconds
    loops = 0
    while time.time() < deadline:
        loops += 1
        _ = loops * loops
    return {"burned_seconds": seconds, "loops": loops}
