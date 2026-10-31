#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ "$#" -ne 1 ]; then
  printf 'Usage: %s provision|verify\n' "$0" >&2
  exit 2
fi
test -f .env || { echo "Start Pocket ID first with ./start.sh" >&2; exit 2; }
exec python3 - "$1" <<'PY'
import base64
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://localhost:1411"
FILE = pathlib.Path(".agent-m2m.json")
MODE = sys.argv[1]
RESOURCE = os.environ.get("LOCAL_MCP_RESOURCE", "http://localhost:8080/mcp")
parsed = urllib.parse.urlparse(RESOURCE)
if parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1", "::1"}:
    raise SystemExit("LOCAL_MCP_RESOURCE must be a loopback HTTP URL for isolated tests")
if MODE not in {"provision", "verify"}:
    raise SystemExit("Expected provision or verify")
API_KEY = ""
for line in pathlib.Path(".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("STATIC_API_KEY="):
        API_KEY = line.partition("=")[2]
if len(API_KEY) < 16:
    raise SystemExit("Local .env does not contain a valid static admin API key")
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def request(method, path, body=None, *, api=False, form=False):
    headers = {}
    if api:
        headers["X-API-KEY"] = API_KEY
    payload = None
    if body is not None:
        if form:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            payload = urllib.parse.urlencode(body).encode()
        else:
            headers["Content-Type"] = "application/json"
            payload = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=payload, headers=headers, method=method)
    try:
        with OPENER.open(req, timeout=10) as res:
            return res.status, json.loads(res.read())
    except urllib.error.HTTPError as error:
        return error.code, {}

def expected(status, value, code, stage):
    if status != code or not isinstance(value, dict):
        raise RuntimeError(f"{stage}: expected HTTP {code}; observed HTTP {status}")
    return value

if MODE == "provision":
    if FILE.exists() or FILE.is_symlink():
        raise SystemExit("Local credentials already exist; run ./agent-m2m.sh verify")
    status, api = request("POST", "/api/apis", {"name": "Local GitHub MCP", "resource": RESOURCE}, api=True)
    api = expected(status, api, 201, "Create local resource")
    ident = api["id"]
    status, perms = request("PUT", f"/api/apis/{ident}/permissions",
                            {"permissions": [{"key": "mcp:access", "name": "MCP access"}]}, api=True)
    perms = expected(status, perms, 200, "Add local scope")
    permission = next(p["id"] for p in perms["permissions"] if p["key"] == "mcp:access")
    status, client = request("POST", "/api/oidc/clients",
                             {"name": "Local Agent M2M", "isPublic": False,
                              "callbackURLs": ["http://localhost:3000/callback"],
                              "pkceEnabled": True}, api=True)
    client = expected(status, client, 201, "Create confidential client")
    client_id = client["id"]
    secret = client.get("createdSecret", {}).get("secret")
    if not secret:
        raise RuntimeError("Pocket ID did not return the confidential client secret")
    status, grant = request("PUT", f"/api/apis/{ident}/clients/{client_id}",
                            {"clientAccess": True, "clientPermissionIds": [permission],
                             "userDelegatedAccess": False, "userDelegatedPermissionIds": []}, api=True)
    expected(status, grant, 200, "Grant local M2M permission")
    fd = os.open(FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump({"client_id": client_id, "client_secret": secret, "resource": RESOURCE}, stream)
        stream.write("\n")
    print("Scoped Pocket ID local MCP client provisioned")
    print("Credentials in .agent-m2m.json (mode 0600); never publish this file")
else:
    if FILE.is_symlink() or not FILE.is_file() or (FILE.stat().st_mode & 0o077):
        raise SystemExit("Local .agent-m2m.json missing or permissions not private (0600)")
    cfg = json.loads(FILE.read_text(encoding="utf-8"))
    form = {"grant_type": "client_credentials", "client_id": cfg["client_id"],
            "client_secret": cfg["client_secret"], "resource": cfg["resource"],
            "scope": "mcp:access"}
    status, token = request("POST", "/api/oidc/token", form, form=True)
    token = expected(status, token, 200, "Issue local access token")
    jwt = token.get("access_token", "")
    if jwt.count(".") != 2 or token.get("token_type", "").lower() != "bearer":
        raise RuntimeError("Pocket ID did not issue a JWT bearer token")
    encoded = jwt.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    audience = claims.get("aud", [])
    if isinstance(audience, str):
        audience = [audience]
    if claims.get("iss") != BASE or cfg["resource"] not in audience or "mcp:access" not in claims.get("scope", "").split():
        raise RuntimeError("Wrong JWT issuer, audience or scope")
    if not isinstance(claims.get("exp"), int):
        raise RuntimeError("JWT expiry missing")
    bad = dict(form, client_secret="invalid-secret-for-negative-test")
    denied, _ = request("POST", "/api/oidc/token", bad, form=True)
    if denied not in {400, 401, 403}:
        raise RuntimeError("Invalid client secret was not denied")
    print("M2M JWT PASS: issuer, audience, scope and expiry validated")
    print(f"Invalid secret denied: HTTP {denied}")
    print("NOTE: this script does not cryptographically verify the JWT signature")
PY
