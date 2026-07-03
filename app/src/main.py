import os
import socket
import time
from typing import Any

import boto3
import redis
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse


app = FastAPI(title="EKS Interview Lab App", version=os.getenv("APP_VERSION", "dev"))


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default)


def redis_client() -> redis.Redis:
    redis_host = env("REDIS_HOST", "interview-app-redis")
    redis_port = int(env("REDIS_PORT", "6379"))
    return redis.Redis(host=redis_host, port=redis_port, socket_timeout=2, decode_responses=True)


@app.get("/")
def root() -> dict[str, Any]:
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
            "/healthz",
            "/readyz",
            "/config",
            "/secret-check",
            "/redis/incr",
            "/aws/identity",
            "/burn?seconds=5",
        ],
    }


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
    }


@app.get("/secret-check")
def secret_check() -> dict[str, Any]:
    value = env("DEMO_API_KEY")
    return {
        "secret_mounted": bool(value),
        "length": len(value),
        "note": "The app never returns the secret value.",
    }


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


@app.get("/burn")
def burn(seconds: int = Query(default=10, ge=1, le=60)) -> dict[str, Any]:
    deadline = time.time() + seconds
    loops = 0
    while time.time() < deadline:
        loops += 1
        _ = loops * loops
    return {"burned_seconds": seconds, "loops": loops}
