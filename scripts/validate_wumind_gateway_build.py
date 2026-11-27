"""Validate the public WuMind URL selected for this Xcode configuration."""
import os
import re
import sys
from urllib.parse import unquote, urlsplit


def address(raw):
    if not raw:
        return None
    url = urlsplit(raw)
    host = url.hostname or ""
    path = unquote(url.path).rstrip("/")
    labels = host.split(".")
    if (url.scheme != "https" or len(labels) < 2
            or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label) for label in labels)
            or url.username is not None or url.password is not None or "?" in raw or "#" in raw
            or labels[-1] in {"example", "invalid", "test", "localhost"}
            or host.endswith((".example.com", ".example.org", ".example.net"))
            or host in {"example.com", "example.org", "example.net", "dash.cloudflare.com",
                        "api.cloudflare.com", "wumind-test.workers.dev", "your-gateway.workers.dev"}
            or set(path.lower().split("/")) & {"admin", "dashboard", "edit", ".", ".."}
            or raw.strip() != raw or "\\" in raw or "%" in url.path):
        raise ValueError()
    return (host, url.port or 443, path)


def validate(env):
    config = env.get("CONFIGURATION")
    if config not in {"Debug", "Testing", "Release"}:
        raise ValueError()
    release = config == "Release"
    active_key = "WUMIND_PRODUCTION_GATEWAY_URL" if release else "WUMIND_TEST_GATEWAY_URL"
    other_key = "WUMIND_TEST_GATEWAY_URL" if release else "WUMIND_PRODUCTION_GATEWAY_URL"
    selected = address(env.get("WUMIND_BUILD_GATEWAY_URL"))
    if selected != address(env.get(active_key)):
        raise ValueError()
    if not selected:
        return
    try:
        other = address(env.get(other_key))
    except ValueError:
        # An unverified endpoint in the other configuration never enters this bundle.
        other = None
    if selected == other or (release and
            re.search(r"(?:^|[-./_])(test|staging|sandbox)(?:[-./_]|$)", selected[0] + selected[2], re.I)):
        raise ValueError()


if __name__ == "__main__":
    try:
        validate(os.environ)
    except ValueError:
        sys.exit("error: Invalid WuMind gateway selection. Check the verified public endpoints for this build configuration.")
