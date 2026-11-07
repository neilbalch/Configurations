#!/usr/bin/env python3
"""Widget-facing LB120 helper.

No long-lived socket: each invocation opens TCP 9999, sends one request,
reads the reply, FINs, and exits. The Kasa app can talk to the bulb in
between widget commands. A local flock only serializes *our* processes.

python-kasa's CLI is fine as a single waited-for command. Plasma used to
SIGTERM it mid-TCP and overlap slider processes. This wrapper still uses
`kasa --type bulb command` for get/toggle, and a one-shot XOR send for
slider sets (same packet, no persistent connection).
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

# Set True only after the LB120 stays pingable. The widget must not
# open TCP while the bulb is recovering.
ENABLE_LAMP_IO = True

LIGHT = "smartlife.iot.smartbulb.lightingservice"
LOCK_PATH = Path.home() / ".cache" / "desklamp-lb120.lock"
MIN_INTERVAL = 0.0
KASA_TIMEOUT = 5
PORT = 9999
XOR_TIMEOUT = 2.0
XOR_IV = 171
MAX_PAYLOAD = 65535
# After FIN, give the bulb a beat to free its single accept slot for the
# Kasa app (or the next widget command). Never keep a socket across calls.
POST_CLOSE_IDLE = 0.05
# UDP get_sysinfo only. `kasa discover list` follows up with TCP to every
# device, and a mid-TCP close knocks the LB120 off Wi-Fi.
DISCOVER_TIMEOUT = 3.0
DISCOVER_PACKETS = 3


def emit(payload: dict, code: int = 0) -> None:
    print(json.dumps(payload), flush=True)
    raise SystemExit(code)


def find_kasa() -> str:
    explicit = os.environ.get("KASA_BIN")
    if explicit:
        return explicit
    for candidate in (
        str(Path.home() / ".local/bin/kasa"),
        shutil.which("kasa") or "",
    ):
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    emit({"ok": False, "error": "kasa CLI not found (pipx install python-kasa)"}, 2)
    raise AssertionError("unreachable")


def last_json(stdout: str) -> dict:
    text = stdout.strip()
    if not text:
        raise ValueError("kasa produced no output")
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass
    for line in reversed(text.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        parsed = json.loads(line)
        if isinstance(parsed, dict):
            return parsed
    raise ValueError(f"unparseable kasa output: {text[:200]}")


def xor_encrypt(plaintext: str) -> bytes:
    data = plaintext.encode("utf-8")
    key = XOR_IV
    out = bytearray(struct.pack(">I", len(data)))
    for byte in data:
        key ^= byte
        out.append(key)
    return bytes(out)


def xor_decrypt(ciphertext: bytes) -> str:
    key = XOR_IV
    out = bytearray()
    for byte in ciphertext:
        out.append(key ^ byte)
        key = byte
    return out.decode("utf-8")


def recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise TimeoutError("lamp closed the connection")
        buf.extend(chunk)
    return bytes(buf)


def xor_query(host: str, payload: dict) -> dict:
    """One request, then a FIN close. The socket does not outlive this call."""
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(XOR_TIMEOUT)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 0)
    try:
        sock.connect((host, PORT))
        sock.sendall(xor_encrypt(raw))
        header = recv_exact(sock, 4)
        (length,) = struct.unpack(">I", header)
        if length < 2 or length > MAX_PAYLOAD:
            raise ValueError(f"implausible response length {length}")
        body = recv_exact(sock, length)
        return json.loads(xor_decrypt(body))
    finally:
        try:
            sock.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        sock.close()
        time.sleep(POST_CLOSE_IDLE)


def unwrap(resp: dict, module: str, method: str) -> dict:
    block = resp.get(module)
    if not isinstance(block, dict):
        raise RuntimeError(f"no {module} in response")
    if block.get("err_code") not in (None, 0):
        raise RuntimeError(f"{module}: {block}")
    result = block.get(method)
    if not isinstance(result, dict):
        raise RuntimeError(f"no {module}.{method} in response")
    if result.get("err_code") not in (None, 0):
        raise RuntimeError(f"{module}.{method}: {result}")
    return result


def kasa_command(host: str, module: str, method: str, params: dict | None = None) -> dict:
    cmd = [
        find_kasa(),
        "--type",
        "bulb",
        "--host",
        host,
        "--timeout",
        str(KASA_TIMEOUT),
        "--json",
        "command",
        "--module",
        module,
        method,
    ]
    if params is not None:
        cmd.append(repr(params))
    proc = subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
        timeout=KASA_TIMEOUT + 2,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or f"kasa exited {proc.returncode}").strip()
        raise RuntimeError(err.splitlines()[-1] if err else f"kasa exited {proc.returncode}")
    return last_json(proc.stdout)


def format_mac(raw: object) -> str:
    hexmac = "".join(ch for ch in str(raw or "") if ch.isalnum())
    if len(hexmac) == 12:
        return ":".join(hexmac[i : i + 2] for i in range(0, 12, 2)).lower()
    return str(raw or "")


def mac_from_sysinfo(info: dict) -> str:
    return format_mac(info.get("mac") or info.get("mic_mac") or "")


def light_from_state(ls: dict, sysinfo: dict | None = None) -> dict:
    on = bool(ls.get("on_off"))
    src = ls
    if (not on) and isinstance(ls.get("dft_on_state"), dict):
        src = ls["dft_on_state"]
    info = sysinfo or {}
    return {
        "ok": True,
        "on": on,
        "brightness": int(src.get("brightness") or 0),
        "color_temp": int(src.get("color_temp") or 0),
        "alias": info.get("alias", ""),
        "model": info.get("model", ""),
        "mac": mac_from_sysinfo(info),
        "host": info.get("host", ""),
    }


def light_from_sysinfo(sysinfo: dict, host: str) -> dict:
    result = light_from_state(sysinfo.get("light_state") or {}, sysinfo)
    result["host"] = host
    return result


def cmd_get(host: str) -> dict:
    sysinfo = kasa_command(host, "system", "get_sysinfo")
    return light_from_sysinfo(sysinfo, host)


def cmd_set(host: str, params: dict) -> dict:
    # Sliders need to be snappy; spawning `kasa` is ~0.5s+. Same XOR payload
    # the CLI would send, without the Python-kasa import/process cost.
    ls = unwrap(
        xor_query(host, {LIGHT: {"transition_light_state": params}}),
        LIGHT,
        "transition_light_state",
    )
    result = light_from_state(ls if isinstance(ls, dict) else {})
    result["host"] = host
    return result


def cmd_toggle(host: str) -> dict:
    sysinfo = kasa_command(host, "system", "get_sysinfo")
    on = bool((sysinfo.get("light_state") or {}).get("on_off"))
    params = {"on_off": 0} if on else {"on_off": 1}
    ls = kasa_command(host, LIGHT, "transition_light_state", params)
    result = light_from_state(ls if isinstance(ls, dict) else {}, sysinfo)
    result["on"] = not on
    result["host"] = host
    return result


class FindError(Exception):
    """Expected discovery failure with a message safe to show in the widget."""


def ipv4_broadcasts() -> list[str]:
    """Global broadcast plus each interface's directed broadcast.

    255.255.255.255 follows the default route, which is the wrong NIC when a
    VPN is up. Directed broadcasts still reach the lamp's subnet.
    """
    targets = ["255.255.255.255"]
    ip_bin = shutil.which("ip")
    if not ip_bin:
        return targets
    try:
        proc = subprocess.run(
            [ip_bin, "-4", "-o", "addr", "show", "up"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return targets
    for line in proc.stdout.splitlines():
        parts = line.split()
        if "brd" not in parts:
            continue
        idx = parts.index("brd")
        if idx + 1 >= len(parts):
            continue
        brd = parts[idx + 1]
        if brd and brd not in targets and brd != "0.0.0.0":
            targets.append(brd)
    return targets


def decode_discovery_datagram(data: bytes) -> dict | None:
    """Legacy discovery replies are XOR'd and have no length header."""
    blobs = [data]
    if len(data) > 4:
        blobs.append(data[4:])
    for blob in blobs:
        try:
            info = json.loads(xor_decrypt(blob).strip("\x00").strip())
        except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
            continue
        if not isinstance(info, dict):
            continue
        system = info.get("system")
        if isinstance(system, dict) and isinstance(system.get("get_sysinfo"), dict):
            return system["get_sysinfo"]
        if "alias" in info or "mic_type" in info or "mac" in info:
            return info
    return None


def select_lamp(devices: dict[str, dict], name: str, mac: str) -> tuple[str, dict]:
    """Pick the desk lamp. MAC wins; otherwise a unique alias match."""
    want_mac = format_mac(mac)
    want_name = name.strip().lower()
    if not want_mac and not want_name:
        raise FindError("find needs a device name or MAC")

    by_name: list[tuple[str, dict]] = []
    for ip, info in devices.items():
        if want_mac and mac_from_sysinfo(info) == want_mac:
            return ip, info
        alias = str(info.get("alias") or "").strip().lower()
        if want_name and alias == want_name:
            by_name.append((ip, info))

    if len(by_name) == 1:
        return by_name[0]
    if len(by_name) > 1:
        hosts = ", ".join(sorted(ip for ip, _ in by_name))
        raise FindError(f"more than one device is named {name}: {hosts}")
    raise FindError(f"Could not find {name} on the network")


def discover_legacy(mac: str, timeout: float = DISCOVER_TIMEOUT) -> dict[str, dict]:
    """Broadcast legacy get_sysinfo on UDP 9999. Never opens TCP."""
    query = json.dumps({"system": {"get_sysinfo": {}}}, separators=(",", ":"))
    packet = xor_encrypt(query)[4:]
    want_mac = format_mac(mac)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    except OSError:
        pass
    found: dict[str, dict] = {}
    try:
        sock.bind(("0.0.0.0", 0))
        targets = ipv4_broadcasts()
        deadline = time.monotonic() + timeout
        spacing = timeout / DISCOVER_PACKETS
        next_send = time.monotonic()
        sent = 0
        while time.monotonic() < deadline:
            now = time.monotonic()
            if sent < DISCOVER_PACKETS and now >= next_send:
                for target in targets:
                    try:
                        sock.sendto(packet, (target, PORT))
                    except OSError:
                        continue
                sent += 1
                next_send = now + spacing
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            sock.settimeout(min(0.2, remaining))
            try:
                data, addr = sock.recvfrom(MAX_PAYLOAD)
            except TimeoutError:
                continue
            except OSError:
                continue
            ip = addr[0]
            if ip in found:
                continue
            info = decode_discovery_datagram(data)
            if info is None:
                continue
            found[ip] = info
            if want_mac and mac_from_sysinfo(info) == want_mac:
                break
        return found
    finally:
        sock.close()


def cmd_find(name: str, mac: str = "") -> dict:
    """Rediscover the lamp after a DHCP change. UDP only; no TCP."""
    ip, info = select_lamp(discover_legacy(mac), name, mac)
    result = light_from_sysinfo(info, ip)
    result["discovered"] = True
    return result


@contextmanager
def exclusive_session():
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK_PATH, "a+", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        raw = fh.read().strip()
        try:
            last = float(raw)
        except ValueError:
            last = 0.0
        gap = MIN_INTERVAL - (time.time() - last)
        if gap > 0:
            time.sleep(gap)
        try:
            yield
        finally:
            fh.seek(0)
            fh.truncate()
            fh.write(str(time.time()))
            fh.flush()
            fcntl.flock(fh, fcntl.LOCK_UN)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="LB120 kasa CLI wrapper for the Plasma widget")
    parser.add_argument("--host", default="", help="Device IP")
    parser.add_argument("--name", default="Desk Corner")
    parser.add_argument("--mac", default="", help="Prefer this MAC when rediscovering")
    parser.add_argument(
        "action",
        choices=("get", "on", "off", "toggle", "brightness", "temperature", "find"),
    )
    parser.add_argument("value", nargs="?", type=int, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not ENABLE_LAMP_IO:
        emit(
            {
                "ok": False,
                "error": "Lamp I/O disabled so the LB120 can stay on Wi-Fi",
            },
            1,
        )
    try:
        if args.action == "find":
            emit(cmd_find(args.name, args.mac))
        if not args.host:
            emit({"ok": False, "error": "--host is required"}, 2)
        if args.action == "get":
            emit(cmd_get(args.host))
        elif args.action == "toggle":
            emit(cmd_toggle(args.host))
        elif args.action == "on":
            emit(cmd_set(args.host, {"on_off": 1}))
        elif args.action == "off":
            emit(cmd_set(args.host, {"on_off": 0}))
        elif args.action == "brightness":
            if args.value is None or not 1 <= args.value <= 100:
                emit({"ok": False, "error": "brightness requires 1-100"}, 2)
            emit(cmd_set(args.host, {"brightness": args.value, "ignore_default": 1}))
        elif args.action == "temperature":
            if args.value is None or not 2700 <= args.value <= 6500:
                emit({"ok": False, "error": "temperature requires 2700-6500"}, 2)
            emit(cmd_set(args.host, {"color_temp": args.value, "ignore_default": 1}))
    except subprocess.TimeoutExpired:
        emit({"ok": False, "error": "kasa timed out"}, 1)
    except FindError as exc:
        emit({"ok": False, "error": str(exc)}, 1)
    except Exception as exc:
        emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, 1)


if __name__ == "__main__":
    with exclusive_session():
        main()
