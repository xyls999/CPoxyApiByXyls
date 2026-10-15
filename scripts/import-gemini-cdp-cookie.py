"""Import only Gemini Google cookies from the dedicated local Edge CDP profile.

This helper never prints cookie values. It is intentionally limited to the
loopback CDP endpoint and the local Argon admin endpoint.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

import websockets

REQUIRED = {
    "SID",
    "HSID",
    "SSID",
    "APISID",
    "SAPISID",
    "__Secure-1PSID",
    "__Secure-1PSIDTS",
}


async def cdp_call(socket, request_id: int, method: str) -> dict:
    await socket.send(json.dumps({"id": request_id, "method": method}))
    while True:
        response = json.loads(await socket.recv())
        if response.get("id") == request_id:
            return response


async def read_gemini_cookies(cdp_url: str) -> list[dict]:
    with urllib.request.urlopen(cdp_url + "/json/list", timeout=5) as response:
        targets = json.load(response)
    page = next(
        (
            target
            for target in targets
            if target.get("type") == "page"
            and "gemini.google.com" in target.get("url", "")
        ),
        None,
    )
    if not page:
        raise RuntimeError("专用 Edge 尚未打开 Gemini 页面")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=20 * 1024 * 1024) as socket:
        response = await cdp_call(socket, 1, "Network.getAllCookies")
    cookies = response.get("result", {}).get("cookies", [])
    return [
        cookie
        for cookie in cookies
        if "google.com" in cookie.get("domain", "") and cookie.get("value")
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cdp", default="http://127.0.0.1:19447")
    parser.add_argument("--admin", default="http://127.0.0.1:18083")
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    try:
        cookies = asyncio.run(read_gemini_cookies(args.cdp))
        names = {cookie["name"] for cookie in cookies}
        missing = sorted(REQUIRED - names)
        if missing:
            print("Gemini Cookie: login required in the dedicated Edge window")
            return 2
        config = json.loads(Path(args.config).read_text(encoding="utf-8"))
        cookie_header = "; ".join(f"{cookie['name']}={cookie['value']}" for cookie in cookies)
        body = json.dumps(
            {
                "label": "Dedicated Gemini Edge auto-import",
                "cookie": cookie_header,
                "note": "Imported locally; cookie values are never logged",
            }
        ).encode("utf-8")
        auth = "Bearer " + config["admin_token"]
        list_request = urllib.request.Request(
            args.admin + "/admin/api/cookies",
            headers={"Authorization": auth},
            method="GET",
        )
        with urllib.request.urlopen(list_request, timeout=15) as response:
            existing = json.load(response).get("items", [])
        for item in existing:
            if item.get("label") != "Dedicated Gemini Edge auto-import":
                continue
            delete_request = urllib.request.Request(
                args.admin + "/admin/api/cookies/" + str(item["id"]),
                headers={"Authorization": auth},
                method="DELETE",
            )
            with urllib.request.urlopen(delete_request, timeout=15):
                pass
        request = urllib.request.Request(
            args.admin + "/admin/api/cookies",
            data=body,
            headers={"Authorization": auth, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            result = json.load(response)
        if result.get("error"):
            print("Gemini Cookie: Argon import rejected")
            return 1
        print("Gemini Cookie: imported from dedicated Edge")
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, urllib.error.URLError) as exc:
        print(f"Gemini Cookie: not imported ({type(exc).__name__})")
        return 1


if __name__ == "__main__":
    sys.exit(main())
