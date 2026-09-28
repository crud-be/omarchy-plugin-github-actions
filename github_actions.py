#!/usr/bin/env python3

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

API = "https://api.github.com"
RUNNING = {"queued", "in_progress", "waiting", "requested", "pending"}


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "github-actions"


def write_private(path, text):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, prefix=".tmp.", delete=False) as temporary:
        temporary.write(text)
    Path(temporary.name).chmod(0o600)
    Path(temporary.name).replace(path)


def load_token():
    # The shell's PATH may lack ~/.local/bin, where gh is often installed.
    gh = shutil.which("gh") or shutil.which("gh", path=str(Path.home() / ".local/bin"))
    if not gh:
        return ""
    try:
        return subprocess.run([gh, "auth", "token"], capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def load_list(name):
    try:
        return [str(item) for item in json.loads((config_dir() / name).read_text(encoding="utf-8"))]
    except (OSError, ValueError, TypeError):
        return []


def api(token, path, method="GET", body=None, raw=False):
    url = path if path.startswith("https://") else API + path
    request = Request(
        url,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github.raw" if raw else "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "omarchy-plugin-github-actions/0.1",
        },
    )
    with urlopen(request, timeout=15) as response:
        data = response.read()
        link = response.headers.get("Link", "")
    if raw:
        return data.decode("utf-8"), link
    return (json.loads(data) if data else None), link


def list_repos(token):
    repos = []
    url = "/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member"
    while url:
        page, link = api(token, url)
        repos.extend(str(repo["full_name"]) for repo in page if not repo.get("archived"))
        match = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = match.group(1) if match else ""
    return repos


def age(timestamp, now=None):
    try:
        then = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))
    except ValueError:
        return ""
    seconds = int(((now or datetime.now(timezone.utc)) - then).total_seconds())
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if seconds >= size:
            return f"{seconds // size}{unit}"
    return "now"


def run_summary(run):
    status = str(run.get("status", ""))
    return {
        "running": status in RUNNING,
        "status": status,
        "conclusion": str(run.get("conclusion") or ""),
        "url": str(run.get("html_url", "")),
        "title": str(run.get("display_title") or run.get("name") or ""),
        "number": int(run.get("run_number") or 0),
        "branch": str(run.get("head_branch") or ""),
        "event": str(run.get("event", "")),
        "age": age(run.get("created_at", "")),
    }


def running_workflows(runs):
    return {run.get("workflow_id") for run in runs if run.get("status") in RUNNING}


def last_run_times(runs):
    latest = {}
    for run in runs:  # API returns newest first
        latest.setdefault(run.get("workflow_id"), str(run.get("created_at") or ""))
    return latest


def by_last_run(workflows):
    # Most recently run first; workflows without a recent run follow by name.
    ordered = sorted(workflows, key=lambda w: w["name"].lower())
    return sorted(ordered, key=lambda w: w["lastRun"], reverse=True)


def repo_actions(token, name):
    base = {"name": name, "url": f"https://github.com/{name}/actions", "defaultBranch": "main", "workflows": []}
    try:
        repo = api(token, f"/repos/{name}")[0]
        workflows = api(token, f"/repos/{name}/actions/workflows?per_page=100")[0].get("workflows", [])
        runs = api(token, f"/repos/{name}/actions/runs?per_page=100")[0].get("workflow_runs", [])
    except HTTPError as error:
        return {**base, "error": "Not found or no access" if error.code == 404 else f"GitHub request failed ({error.code})"}
    except (URLError, OSError, KeyError, ValueError):
        return {**base, "error": "Could not load workflows"}
    running = running_workflows(runs)
    last_run = last_run_times(runs)
    items = []
    for workflow in workflows:
        path = str(workflow.get("path", ""))
        items.append(
            {
                "id": str(workflow["id"]),
                "name": str(workflow.get("name") or path),
                "path": path,
                "active": workflow.get("state") == "active",
                "dispatchable": path.startswith(".github/workflows/") and workflow.get("state") == "active",
                "running": workflow["id"] in running,
                "lastRun": last_run.get(workflow["id"], ""),
                "url": f"https://github.com/{name}/actions/workflows/{path.rsplit('/', 1)[-1]}",
            }
        )
    return {**base, "defaultBranch": str(repo.get("default_branch") or "main"), "workflows": by_last_run(items)}


def with_token(action):
    token = load_token()
    if not token:
        return reply({"ok": False, "auth": False, "error": "Run `gh auth login` in a terminal to sign in"})
    try:
        return action(token)
    except HTTPError as error:
        if error.code == 401:
            return reply({"ok": False, "auth": False, "error": "gh credentials were rejected, run `gh auth login` again"})
        return reply({"ok": False, "auth": True, "error": f"GitHub request failed ({error.code})"})
    except (URLError, OSError):
        return reply({"ok": False, "auth": True, "error": "Could not connect to GitHub"})


def print_list(token):
    user = api(token, "/user")[0]
    names = load_list("repos.json")
    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(lambda name: repo_actions(token, name), names))
    return reply({"ok": True, "user": str(user.get("login", "")), "repos": results, "hidden": load_list("hidden.json")})


def print_repos(token):
    return reply({"ok": True, "repos": list_repos(token)})


def print_runs(token, repo, workflow_id):
    runs = api(token, f"/repos/{repo}/actions/workflows/{workflow_id}/runs?per_page=3")[0].get("workflow_runs", [])
    return reply({"ok": True, "runs": [run_summary(run) for run in runs]})


def dispatch_inputs(document):
    triggers = document.get("on", document.get(True))  # YAML 1.1 parses a bare `on` key as True
    if isinstance(triggers, str):
        triggers = [triggers]
    if isinstance(triggers, list):
        return "workflow_dispatch" in triggers, []
    if not isinstance(triggers, dict) or "workflow_dispatch" not in triggers:
        return False, []
    inputs = (triggers.get("workflow_dispatch") or {}).get("inputs") or {}
    result = []
    for key, spec in inputs.items():
        spec = spec or {}
        kind = str(spec.get("type", "string"))
        default = spec.get("default", "")
        if kind == "boolean":
            default = str(default).lower() == "true"
        result.append(
            {
                "key": str(key),
                "description": str(spec.get("description") or key),
                "type": kind,
                "required": bool(spec.get("required", False)),
                "default": default if isinstance(default, bool) else ("" if default is None else str(default)),
                "options": [str(option) for option in spec.get("options") or []],
            }
        )
    return True, result


def print_inputs(repo, path, ref):
    try:
        import yaml
    except ImportError:
        return reply({"ok": False, "error": "python-yaml is not installed"})
    try:
        text = api(load_token(), f"/repos/{repo}/contents/{quote(path)}?ref={quote(ref)}", raw=True)[0]
        dispatch, inputs = dispatch_inputs(yaml.safe_load(text) or {})
    except HTTPError as error:
        return reply({"ok": False, "error": f"Could not read workflow file ({error.code})"})
    except (URLError, OSError, yaml.YAMLError, AttributeError):
        return reply({"ok": False, "error": "Could not read workflow file"})
    if not dispatch:
        return reply({"ok": False, "error": "This workflow has no workflow_dispatch trigger"})
    return reply({"ok": True, "inputs": inputs})


def dispatch(repo, workflow_id, request):
    try:
        api(load_token(), f"/repos/{repo}/actions/workflows/{workflow_id}/dispatches", "POST", request)
    except HTTPError as error:
        try:
            message = json.loads(error.read()).get("message", "")
        except ValueError:
            message = ""
        return reply({"ok": False, "error": message or f"GitHub request failed ({error.code})"})
    except (URLError, OSError):
        return reply({"ok": False, "error": "Could not connect to GitHub"})
    return reply({"ok": True})


def reply(payload):
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0 if payload.get("ok") else 1


def main(arguments):
    command = arguments[1] if len(arguments) > 1 else "list"
    if command == "list":
        return with_token(print_list)
    if command == "repos":
        return with_token(print_repos)
    if command == "runs" and len(arguments) == 4:
        return with_token(lambda token: print_runs(token, *arguments[2:4]))
    if command in ("set-hidden", "set-repos"):
        name = "hidden.json" if command == "set-hidden" else "repos.json"
        write_private(config_dir() / name, json.dumps([str(item) for item in json.loads(sys.stdin.readline())]))
        return reply({"ok": True})
    if command == "inputs" and len(arguments) == 5:
        return print_inputs(*arguments[2:5])
    if command == "dispatch" and len(arguments) == 4:
        return dispatch(arguments[2], arguments[3], json.loads(sys.stdin.readline()))
    print("Usage: github_actions.py list|repos|runs <repo> <id>|set-hidden|set-repos|inputs <repo> <path> <ref>|dispatch <repo> <id>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
