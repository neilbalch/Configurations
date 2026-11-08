#!/usr/bin/env python3
"""Recent rclone bisync transfers for the Google Drive Plasma widget.

The audit log calls the remote Path1 and the local folder Path2.
"Queue copy to Path2" is a download. "Queue copy to Path1" is an upload.
"Queue delete" names the side that loses the file. Completion lines
("Copied", "Deleted") do not repeat the direction, so they are paired
with the earlier queue line for that path.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from collections import defaultdict, deque
from datetime import datetime, timedelta
from pathlib import Path

DEFAULT_LOG = Path.home() / ".local/share/rclone/logs/audit.log"
DEFAULT_LOCAL = Path.home() / "GoogleDrive"
TAIL_BYTES = 4_000_000
DEFAULT_LIMIT = 30

LINE_RE = re.compile(
    r"^(?P<ts>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\s+"
    r"(?:(?P<level>INFO|NOTICE|ERROR|CRITICAL)\s+:\s+)?"
    r"(?P<msg>.*)$"
)
QUEUE_RE = re.compile(
    r"^- (Path[12])\s+(Queue copy to Path[12]|Queue delete)\s+- (.+)$"
)
REMOTE_RE = re.compile(r"^gdrive(?:\{[^}]*\})?:(.*)$")
COPY_SUFFIXES = (
    (": Multi-thread Copied (replaced existing)", "replaced"),
    (": Multi-thread Copied (new)", "new"),
    (": Copied (replaced existing)", "replaced"),
    (": Copied (new)", "new"),
    (": Copied (server-side copy)", "server"),
)


def emit(payload: dict, code: int = 0) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    raise SystemExit(code)


def read_tail(path: Path, max_bytes: int = TAIL_BYTES) -> str:
    """Read the last complete lines. A trailing partial write is left out."""
    with path.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        start = max(0, size - max_bytes)
        handle.seek(start)
        if start > 0:
            handle.readline()
        data = handle.read()
    if data and not data.endswith(b"\n"):
        if b"\n" in data:
            data = data.rsplit(b"\n", 1)[0]
        else:
            data = b""
    return data.decode("utf-8", errors="replace")


def bisync_running() -> bool:
    proc_root = Path("/proc")
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return False
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        parts = [part for part in raw.decode("utf-8", "replace").split("\x00") if part]
        if not parts:
            continue
        if os.path.basename(parts[0]) == "rclone" and "bisync" in parts:
            return True
    return False


def services_active() -> bool | None:
    """True when the watcher or the poll timer is active. None if systemd cannot say."""
    import subprocess

    try:
        proc = subprocess.run(
            ["systemctl", "--user", "is-active", "gdrive-watcher.service", "gdrive-poll.timer"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if not lines:
        return None
    return any(line == "active" for line in lines)


def parse_stamp(text: str) -> datetime | None:
    try:
        return datetime.strptime(text, "%Y/%m/%d %H:%M:%S")
    except ValueError:
        return None


def format_ago(then: datetime, now: datetime) -> str:
    seconds = int((now - then).total_seconds())
    if seconds < 60:
        return "Just now"
    minutes = seconds // 60
    if minutes < 60:
        return "1 minute ago" if minutes == 1 else f"{minutes} minutes ago"
    hours = seconds // 3600
    if hours < 24:
        return "1 hour ago" if hours == 1 else f"{hours} hours ago"
    days = seconds // 86400
    if days < 7:
        return "1 day ago" if days == 1 else f"{days} days ago"
    return then.strftime("%b %-d, %-I:%M %p")


def shorten(text: str, limit: int = 180) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def normalize_rel(rel: str) -> str:
    rel = rel.strip().replace("\\", "/")
    while rel.startswith("./"):
        rel = rel[2:]
    return rel.strip("/")


def to_rel(dest: str, local_dir: str) -> str | None:
    dest = dest.strip()
    local = os.path.normpath(local_dir)
    if dest.startswith("/"):
        norm = os.path.normpath(dest)
        prefix = local + os.sep
        if norm == local:
            return ""
        if norm.startswith(prefix):
            return normalize_rel(norm[len(local) :])
    match = REMOTE_RE.match(dest)
    if match:
        return normalize_rel(match.group(1))
    if dest and not dest.startswith("/") and ":" not in dest.split("/", 1)[0]:
        return normalize_rel(dest)
    return None


def copy_kind(msg: str) -> tuple[str, str] | None:
    for suffix, kind in COPY_SUFFIXES:
        if msg.endswith(suffix):
            return msg[: -len(suffix)].strip(), kind
    if msg.endswith(": Deleted"):
        return msg[: -len(": Deleted")].strip(), "deleted"
    return None


def is_fatal(level: str | None, msg: str) -> bool:
    if level == "CRITICAL":
        return True
    if msg.startswith("Failed to "):
        return True
    if "Bisync aborted" in msg or msg.startswith("Bisync critical"):
        return True
    return False


def format_size(num: int) -> str:
    size = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            if unit == "B":
                return f"{num} B"
            if size >= 10:
                return f"{round(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{num} B"


def current_size(path: str, check: bool) -> str:
    if not check:
        return ""
    try:
        if os.path.isfile(path):
            return format_size(os.path.getsize(path))
    except OSError:
        return ""
    return ""


def action_for(direction: str, kind: str, in_progress: bool) -> tuple[str, str, str]:
    """Return action id, label, and icon name."""
    if in_progress and kind == "deleted" and direction == "push":
        return "removing_remote", "Removing from Drive", "edit-delete"
    if in_progress and kind == "deleted":
        return "removing", "Removing", "edit-delete"
    if in_progress and direction == "push":
        return "uploading", "Uploading", "cloud-upload"
    if in_progress:
        return "downloading", "Downloading", "cloud-download"
    if kind == "deleted" and direction == "push":
        return "removed_remote", "Removed from Drive", "edit-delete"
    if kind == "deleted":
        return "removed", "Removed", "edit-delete"
    if direction == "push":
        return "uploaded", "Uploaded", "cloud-upload"
    if direction == "pull" and kind == "replaced":
        return "updated", "Updated from Drive", "cloud-download"
    if direction == "pull":
        return "downloaded", "Downloaded", "cloud-download"
    return "synced", "Synced", "cloudstatus"


def make_event(
    when: datetime,
    rel: str,
    direction: str,
    kind: str,
    local_dir: str,
    now: datetime,
    in_progress: bool,
    check_exists: bool,
) -> dict:
    rel = normalize_rel(rel)
    folder, name = os.path.split(rel)
    if not name:
        name = rel or "(Google Drive)"
        folder = ""
    action, label, icon = action_for(direction, kind, in_progress)
    full = os.path.join(local_dir, rel) if rel else local_dir
    exists = os.path.exists(full) if check_exists and rel else False
    if not check_exists:
        open_path = full
    elif exists:
        open_path = full
    else:
        parent = os.path.dirname(full)
        open_path = parent if parent and os.path.isdir(parent) else local_dir
    parts = [part for part in (folder, label) if part]
    if not in_progress:
        parts.append(format_ago(when, now))
    return {
        "time": when.strftime("%Y-%m-%dT%H:%M:%S"),
        "ago": format_ago(when, now),
        "path": rel,
        "name": name,
        "folder": folder,
        "direction": direction,
        "action": action,
        "label": label,
        "icon": icon,
        "subtitle": " · ".join(parts),
        "size": current_size(full, check_exists),
        "in_progress": in_progress,
        "local_path": full,
        "open_path": open_path,
        "exists": exists,
    }


def empty_status() -> dict:
    return {
        "ok": True,
        "phase": "idle",
        "message": "Waiting for the first sync",
        "detail": "",
        "last_scan_started": None,
        "last_scan_finished": None,
        "last_error": "",
        "active": [],
        "events": [],
    }


def parse_log(
    text: str,
    local_dir: str,
    *,
    services_active: bool | None,
    bisync_running: bool,
    now: datetime,
    limit: int,
    check_exists: bool,
) -> dict:
    pending_copies: dict[str, deque] = defaultdict(deque)
    pending_deletes: dict[str, deque] = defaultdict(deque)
    events: list[dict] = []
    scan_open = False
    failed = False
    last_error = ""
    last_started: datetime | None = None
    last_finished: datetime | None = None

    def remember_queue(rel: str, direction: str, kind: str, when: datetime) -> None:
        slot = {"direction": direction, "kind": kind, "time": when}
        if kind == "deleted":
            pending_deletes[rel].append(slot)
        else:
            pending_copies[rel].append(slot)

    for raw in text.splitlines():
        match = LINE_RE.match(raw.strip())
        if not match:
            continue
        when = parse_stamp(match.group("ts"))
        if when is None:
            continue
        level = match.group("level")
        msg = match.group("msg").strip()
        if msg.startswith("Synching Path1"):
            scan_open = True
            failed = False
            last_error = ""
            last_started = when
            pending_copies.clear()
            pending_deletes.clear()
            continue
        if msg == "Bisync successful":
            scan_open = False
            failed = False
            last_error = ""
            last_finished = when
            pending_copies.clear()
            pending_deletes.clear()
            continue
        if is_fatal(level, msg):
            scan_open = False
            failed = True
            last_error = msg
            last_finished = when
            pending_copies.clear()
            pending_deletes.clear()
            continue
        if level == "ERROR":
            failed = True
            last_error = msg
            continue
        queued = QUEUE_RE.match(msg)
        if queued:
            side, action, dest = queued.groups()
            rel = to_rel(dest, local_dir)
            if rel is None:
                continue
            if action == "Queue copy to Path2":
                remember_queue(rel, "pull", "new", when)
            elif action == "Queue copy to Path1":
                remember_queue(rel, "push", "new", when)
            elif side == "Path1":
                remember_queue(rel, "push", "deleted", when)
            else:
                remember_queue(rel, "pull", "deleted", when)
            continue
        result = copy_kind(msg)
        if result is None:
            continue
        rel, kind = result
        rel = normalize_rel(rel)
        if not rel:
            continue
        pool = pending_deletes if kind == "deleted" else pending_copies
        slot = pool[rel].popleft() if pool[rel] else None
        direction = slot["direction"] if slot else "unknown"
        events.append(
            make_event(
                when,
                rel,
                direction,
                kind,
                local_dir,
                now,
                False,
                check_exists,
            )
        )

    if scan_open and not bisync_running:
        scan_open = False
        failed = True
        if not last_error:
            last_error = "The last sync did not finish"
        pending_copies.clear()
        pending_deletes.clear()

    if scan_open and bisync_running:
        phase = "syncing"
    elif failed and last_error:
        phase = "error"
    elif services_active is False:
        phase = "paused"
    elif last_finished is None and not events:
        phase = "idle"
    else:
        phase = "idle"

    active: list[dict] = []
    if phase == "syncing":
        inflight = []
        for pool in (pending_copies, pending_deletes):
            for rel, slots in pool.items():
                for slot in slots:
                    inflight.append((slot["time"], rel, slot["direction"], slot["kind"]))
        inflight.sort(key=lambda item: item[0], reverse=True)
        for when, rel, direction, kind in inflight[:20]:
            active.append(
                make_event(when, rel, direction, kind, local_dir, now, True, check_exists)
            )

    if phase == "syncing":
        count = len(active)
        if count == 1:
            message = "Syncing 1 file…"
        elif count > 1:
            message = f"Syncing {count} files…"
        else:
            message = "Looking for changes…"
        detail = "Checking now"
    elif phase == "error":
        message = "Can't sync"
        detail = shorten(last_error or "The last sync did not finish")
    elif phase == "paused":
        message = "Sync is not running"
        detail = f"Last checked {format_ago(last_finished, now)}" if last_finished else ""
    elif last_finished is None and not events:
        message = "Waiting for the first sync"
        detail = ""
    else:
        message = "Everything is up to date"
        detail = f"Last checked {format_ago(last_finished, now)}" if last_finished else ""

    newest = list(reversed(events))
    if limit > 0:
        newest = newest[:limit]
    return {
        "ok": True,
        "phase": phase,
        "message": message,
        "detail": detail,
        "last_scan_started": last_started.strftime("%Y-%m-%dT%H:%M:%S") if last_started else None,
        "last_scan_finished": last_finished.strftime("%Y-%m-%dT%H:%M:%S") if last_finished else None,
        "last_error": shorten(last_error) if last_error else "",
        "active": active,
        "events": newest,
    }


def error_payload(message: str, detail: str = "") -> dict:
    payload = empty_status()
    payload["ok"] = False
    payload["phase"] = "error"
    payload["message"] = message
    payload["detail"] = detail
    payload["last_error"] = detail or message
    return payload


def status(log_path: Path, local_dir: Path, limit: int) -> dict:
    if not log_path.is_file():
        return error_payload("Sync log not found", str(log_path))
    try:
        text = read_tail(log_path)
    except OSError as exc:
        return error_payload("Could not read the sync log", str(exc))
    payload = parse_log(
        text,
        str(local_dir),
        services_active=services_active(),
        bisync_running=bisync_running(),
        now=datetime.now(),
        limit=limit,
        check_exists=True,
    )
    payload["log_path"] = str(log_path)
    payload["local_dir"] = str(local_dir)
    return payload


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_format_size() -> None:
    expect(format_size(0) == "0 B", format_size(0))
    expect(format_size(512) == "512 B", format_size(512))
    expect(format_size(1536) == "1.5 KB", format_size(1536))
    expect(format_size(12 * 1024) == "12 KB", format_size(12 * 1024))
    expect(format_size(1536 * 1024) == "1.5 MB", format_size(1536 * 1024))


def test_format_ago() -> None:
    now = datetime(2026, 11, 7, 12, 0, 0)
    expect(format_ago(now - timedelta(seconds=10), now) == "Just now", "just now")
    expect(format_ago(now - timedelta(seconds=59), now) == "Just now", "59s")
    expect(format_ago(now - timedelta(minutes=1), now) == "1 minute ago", "1 minute")
    expect(format_ago(now - timedelta(minutes=5), now) == "5 minutes ago", "5 minutes")
    expect(format_ago(now - timedelta(hours=1), now) == "1 hour ago", "1 hour")
    expect(format_ago(now - timedelta(hours=4), now) == "4 hours ago", "4 hours")
    expect(format_ago(now - timedelta(days=2), now) == "2 days ago", "2 days")


def test_tail_drops_partial_line() -> None:
    handle = tempfile.NamedTemporaryFile(delete=False)
    try:
        handle.write(b"2026/11/07 13:00:00 INFO  : Synching Path1\npartial line")
        handle.close()
        text = read_tail(Path(handle.name), max_bytes=1000)
        expect("partial" not in text, "partial tail line leaked")
        expect("Synching" in text, "complete line missing")
        whole = tempfile.NamedTemporaryFile(delete=False)
        try:
            whole.write(b"alpha\nbeta\n")
            whole.close()
            full = read_tail(Path(whole.name), max_bytes=1000)
            expect(full == "alpha\nbeta\n", f"short file read {full!r}")
        finally:
            os.unlink(whole.name)
    finally:
        os.unlink(handle.name)


SAMPLE = """
2026/11/07 09:24:42 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 09:24:50 INFO  : Path1:   23 changes:   20 new,    1 newer,    0 older,    2 deleted
2026/11/07 09:25:16 INFO  : Applying changes
2026/11/07 09:25:16 INFO  : - Path1    Queue copy to Path2                 - /home/neil/GoogleDrive/Dungeon Crawler Carl by Matt Dinniman.epub
2026/11/07 09:25:16 INFO  : - Path1    Queue copy to Path2                 - /home/neil/GoogleDrive/Files/NeilBDatabase.kdbx
2026/11/07 09:25:16 INFO  : - Path1    Queue copy to Path2                 - /home/neil/GoogleDrive/SMS Backup/sms-20261106204521.xml
2026/11/07 09:25:16 INFO  : - Path2    Queue delete                        - /home/neil/GoogleDrive/Rishabh Character Assessment.docx
2026/11/07 09:25:16 INFO  : - Path1    Do queued copies to                 - Path2
2026/11/07 09:25:22 INFO  : Dungeon Crawler Carl by Matt Dinniman.epub: Copied (new)
2026/11/07 09:25:34 INFO  : Files/NeilBDatabase.kdbx: Copied (replaced existing)
2026/11/07 10:16:27 INFO  : SMS Backup/sms-20261106204521.xml: Multi-thread Copied (new)
2026/11/07 10:16:27 INFO  : Rishabh Character Assessment.docx: Deleted
2026/11/07 10:17:10 INFO  : Bisync successful
2026/11/07 13:21:03 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:21:03 INFO  : - Path2    Queue copy to Path1                 - gdrive{5tQS1}:/Files/NeilBDatabase.kdbx
2026/11/07 13:21:05 INFO  : Files/NeilBDatabase.kdbx: Copied (replaced existing)
2026/11/07 13:21:11 INFO  : Bisync successful
2026/11/07 13:25:00 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:25:01 INFO  : - Path1    Queue delete                        - gdrive{5tQS1}:/Old/finished.txt
2026/11/07 13:25:02 INFO  : Old/finished.txt: Deleted
2026/11/07 13:25:03 INFO  : Bisync successful
2026/11/07 13:26:00 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:26:01 INFO  : mystery.txt: Copied (new)
2026/11/07 13:26:02 INFO  : Bisync successful
2026/11/07 13:29:28 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:29:28 INFO  : No changes found
2026/11/07 13:29:28 INFO  : Bisync successful
2026/11/07 13:30:00 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:30:01 INFO  : - Path1    Queue copy to Path2                 - /home/neil/GoogleDrive/Notes/todo.txt
2026/11/07 13:30:02 INFO  : - Path1    Queue delete                        - gdrive{5tQS1}:/Old/gone.txt
"""


def test_sample() -> None:
    now = datetime(2026, 11, 7, 13, 40, 0)
    local = "/home/neil/GoogleDrive"
    running = parse_log(
        SAMPLE,
        local,
        services_active=True,
        bisync_running=True,
        now=now,
        limit=30,
        check_exists=False,
    )
    expect(running["phase"] == "syncing", running["phase"])
    expect(running["message"] == "Syncing 2 files…", running["message"])
    active_paths = [item["path"] for item in running["active"]]
    expect(active_paths == ["Old/gone.txt", "Notes/todo.txt"], str(active_paths))
    expect(running["active"][0]["action"] == "removing_remote", running["active"][0]["action"])
    expect(running["active"][1]["label"] == "Downloading", running["active"][1]["label"])

    by_path: dict[str, dict] = {}
    for item in running["events"]:
        by_path.setdefault(item["path"], item)
    epub = by_path["Dungeon Crawler Carl by Matt Dinniman.epub"]
    expect(epub["direction"] == "pull" and epub["action"] == "downloaded", str(epub))
    sms = by_path["SMS Backup/sms-20261106204521.xml"]
    expect(sms["direction"] == "pull" and sms["action"] == "downloaded", str(sms))
    kdbx_events = [item for item in running["events"] if item["path"] == "Files/NeilBDatabase.kdbx"]
    expect(len(kdbx_events) == 2, str(kdbx_events))
    kdbx = kdbx_events[0]
    expect(kdbx["direction"] == "push" and kdbx["action"] == "uploaded", str(kdbx))
    expect(kdbx_events[1]["action"] == "updated" and kdbx_events[1]["direction"] == "pull", str(kdbx_events[1]))
    removed = by_path["Rishabh Character Assessment.docx"]
    expect(removed["direction"] == "pull" and removed["action"] == "removed", str(removed))
    remote_gone = by_path["Old/finished.txt"]
    expect(remote_gone["action"] == "removed_remote" and remote_gone["direction"] == "push", str(remote_gone))
    mystery = by_path["mystery.txt"]
    expect(mystery["action"] == "synced" and mystery["direction"] == "unknown", str(mystery))
    times = [item["time"] for item in running["events"]]
    expect(times == sorted(times, reverse=True), "events are not newest first")

    dead = parse_log(
        SAMPLE,
        local,
        services_active=True,
        bisync_running=False,
        now=now,
        limit=30,
        check_exists=False,
    )
    expect(dead["phase"] == "error", dead["phase"])
    expect(dead["message"] == "Can't sync", dead["message"])
    expect("did not finish" in dead["detail"], dead["detail"])
    expect(dead["active"] == [], "dead scan still listed active files")

    paused_text = """
2026/11/07 13:00:00 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 13:00:10 INFO  : No changes found
2026/11/07 13:00:10 INFO  : Bisync successful
"""
    paused = parse_log(
        paused_text,
        local,
        services_active=False,
        bisync_running=False,
        now=now,
        limit=10,
        check_exists=False,
    )
    expect(paused["phase"] == "paused", paused["phase"])
    expect(paused["message"] == "Sync is not running", paused["message"])

    failed_text = """
2026/11/07 12:00:00 INFO  : Synching Path1 "gdrive{5tQS1}:/" with Path2 "/home/neil/GoogleDrive/"
2026/11/07 12:00:01 ERROR : googleapi: Error 401: Request had invalid authentication credentials.
2026/11/07 12:00:01 Failed to bisync: couldn't list directory
"""
    failed = parse_log(
        failed_text,
        local,
        services_active=True,
        bisync_running=False,
        now=now,
        limit=10,
        check_exists=False,
    )
    expect(failed["phase"] == "error", failed["phase"])
    expect("couldn't list directory" in failed["detail"], failed["detail"])


def selftest() -> None:
    test_format_size()
    test_format_ago()
    test_tail_drops_partial_line()
    test_sample()
    print("selftest ok")


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize recent rclone bisync transfers")
    parser.add_argument("--log", default=str(DEFAULT_LOG), help="rclone audit log")
    parser.add_argument("--local", default=str(DEFAULT_LOCAL), help="local Google Drive directory")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="completed events to keep")
    parser.add_argument("--selftest", action="store_true", help="run parser checks and exit")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if args.selftest:
        try:
            selftest()
        except AssertionError as exc:
            print(f"selftest failed: {exc}", file=sys.stderr)
            raise SystemExit(1) from exc
        return
    limit = args.limit if args.limit and args.limit > 0 else DEFAULT_LIMIT
    payload = status(Path(args.log), Path(args.local), limit)
    emit(payload, 0 if payload.get("ok") else 1)


if __name__ == "__main__":
    main()
