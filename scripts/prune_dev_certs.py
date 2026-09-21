#!/usr/bin/env python3
"""Delete App Store Connect certificates created by CI ("Created via API").

Uses only the Python standard library plus the openssl CLI to build an ES256 JWT,
so it runs on stock GitHub macOS runners without pip installs.

Usage: prune_dev_certs.py /path/to/AuthKey_XXXX.p8
Requires env ASC_KEY_ID and ASC_ISSUER_ID.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_int(der: bytes, idx: int):
    assert der[idx] == 0x02, "expected INTEGER"
    length = der[idx + 1]
    start = idx + 2
    return der[start:start + length], start + length


def der_to_raw(der: bytes) -> bytes:
    idx = 1
    if der[idx] & 0x80:
        idx += 1 + (der[idx] & 0x7F)
    else:
        idx += 1
    r, idx = _der_int(der, idx)
    s, idx = _der_int(der, idx)
    strip = lambda b: b.lstrip(b"\x00").rjust(32, b"\x00")
    return strip(r) + strip(s)


def make_token(key_path: str) -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return signing_input + "." + b64url(der_to_raw(der))


def request(token: str, method: str, path: str, params=None):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url, method=method, headers={"Authorization": "Bearer " + token}
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.load(exc)
        except Exception:
            return exc.code, {}


def main() -> int:
    key_path = sys.argv[1]
    token = make_token(key_path)
    status, body = request(token, "GET", "/certificates", {"limit": "200"})
    if status != 200:
        print("Could not list certificates:", status, body)
        return 0
    removed = 0
    for cert in body.get("data", []):
        attrs = cert.get("attributes", {})
        if attrs.get("displayName") == "Created via API":
            code, _ = request(token, "DELETE", "/certificates/" + cert["id"])
            print(f"deleted certificate {cert['id']} ({code})")
            removed += 1
    print(f"pruned {removed} CI-created certificate(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
