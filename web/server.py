from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import base64
import hmac
import hashlib
import json
import os
import time
from pathlib import Path
from urllib.parse import quote


STATIC_DIR = Path(__file__).with_name("static")


def _env(name, default=None):
    value = os.environ.get(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


METABASE_SITE_URL = _env("METABASE_SITE_URL", "http://localhost:3000").rstrip("/")
METABASE_EMBEDDING_SECRET = _env("METABASE_EMBEDDING_SECRET")
METABASE_DASHBOARD_ID = int(_env("METABASE_DASHBOARD_ID", "2"))
JWT_TTL_SECONDS = int(_env("METABASE_JWT_TTL_SECONDS", "600"))


def _base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _sign_guest_token(entity_type, entity_id):
    now = int(time.time())
    payload = {
        "resource": {entity_type: entity_id},
        "params": {},
        "iat": now,
        "exp": now + JWT_TTL_SECONDS,
    }
    header = {"alg": "HS256", "typ": "JWT"}

    encoded_header = _base64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    encoded_payload = _base64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")
    signature = hmac.new(
        METABASE_EMBEDDING_SECRET.encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()

    return f"{encoded_header}.{encoded_payload}.{_base64url(signature)}", payload["exp"]


class AppHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_POST(self):
        if self.path != "/api/metabase/guest-token":
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(content_length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON body"})
            return

        entity_type = body.get("entityType")
        entity_id = body.get("entityId")

        if entity_type != "dashboard" or entity_id != METABASE_DASHBOARD_ID:
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": "Only the configured Metabase dashboard can be embedded"},
            )
            return

        token, expires_at = _sign_guest_token(entity_type, entity_id)
        iframe_url = (
            f"{METABASE_SITE_URL}/embed/dashboard/{quote(token)}"
            "#bordered=true&titled=true"
        )
        self._send_json(
            HTTPStatus.OK,
            {
                "token": token,
                "iframeUrl": iframe_url,
                "expiresAt": expires_at,
            },
        )

    def _send_json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), AppHandler)
    print(f"Web app listening on http://0.0.0.0:{port}", flush=True)
    server.serve_forever()
