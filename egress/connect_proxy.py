"""Minimal HTTP CONNECT proxy: the GNB data centre's only route to Konnect.

The Kong data plane sends its hybrid (config + telemetry) connections through
this proxy (KONG_CLUSTER_USE_PROXY=on). Stopping this container is the demo's
"Konnect link cut"; model and tool traffic never passes through it.
Only *.konghq.com:443 is allowed, so it can't be used as a general proxy.
"""
import asyncio
import datetime
import os

LISTEN_PORT = int(os.environ.get("PORT", "3128"))
ALLOWED_SUFFIX = os.environ.get("ALLOWED_SUFFIX", ".konghq.com")


def log(msg: str) -> None:
    print(f"{datetime.datetime.now():%H:%M:%S} konnect-egress {msg}", flush=True)


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        writer.close()


async def handle(client_r: asyncio.StreamReader, client_w: asyncio.StreamWriter) -> None:
    try:
        head = await asyncio.wait_for(client_r.readuntil(b"\r\n\r\n"), timeout=10)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError):
        client_w.close()
        return
    method, target, *_ = head.split(b"\r\n", 1)[0].decode(errors="replace").split(" ")
    host, _, port = target.rpartition(":")
    if method != "CONNECT" or not host.endswith(ALLOWED_SUFFIX) or port != "443":
        log(f"DENY {method} {target}")
        client_w.write(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        await client_w.drain()
        client_w.close()
        return
    try:
        up_r, up_w = await asyncio.wait_for(asyncio.open_connection(host, int(port)), timeout=10)
    except (OSError, asyncio.TimeoutError) as exc:
        log(f"FAIL {target}: {exc}")
        client_w.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        await client_w.drain()
        client_w.close()
        return
    log(f"OPEN {target}")
    client_w.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    await client_w.drain()
    await asyncio.gather(pipe(client_r, up_w), pipe(up_r, client_w))
    log(f"CLOSE {target}")


async def main() -> None:
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN_PORT)
    log(f"listening on :{LISTEN_PORT}, allowing *{ALLOWED_SUFFIX}:443 only")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
