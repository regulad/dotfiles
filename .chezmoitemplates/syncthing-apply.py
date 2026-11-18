"""155-syncthing's REST half on Linux and macOS (00-nt/155-syncthing does the
same in PowerShell): applies .chezmoidata/syncthing.toml to this node's
running Syncthing. The hub becomes this node's introducer, at its tailnet
address; each folder exists at its path and is shared with the hub; the
options are set. It adds and updates, and never removes anything, so devices
and folders added in the GUI stay.

argv: the REST base URL, the hub's device ID, the desired-state JSON
(.chezmoitemplates/syncthing-desired.json). An empty hub ID means this is
the hub: aboriginal's chezmoi runs with dummy secrets, so it never decrypts
the ID, and the only dummy-secrets host that runs this is the hub (see
.chezmoiignore.tmpl). The API key comes in ST_APIKEY,
an environment variable rather than an argument, since a process's arguments
are readable by every user.

Syncthing's REST API (docs.syncthing.net/dev/rest.html) is "subject to
change" but stable in what this uses, the same on 1.29 (Ubuntu's) and 2.x.
PATCH replaces lists whole, so a folder's devices are read, extended and
written back.
"""
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

base = sys.argv[1].rstrip("/")
hub_id = sys.argv[2]
desired = json.loads(sys.argv[3])
api_key = os.environ["ST_APIKEY"]
# Syncthing's own self-signed certificate, on loopback.
context = ssl._create_unverified_context() if base.startswith("https:") else None


def say(level, message):
    print("{}: {}".format(level, message), file=sys.stderr)


def call(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header("X-API-Key", api_key)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, context=context, timeout=30) as response:
            raw = response.read()
    except urllib.error.HTTPError as err:
        if method == "GET" and err.code == 404:
            return None
        detail = err.read().decode("utf-8", "replace").strip()
        say("error", "Syncthing answered {} {} with HTTP {}: {}".format(method, path, err.code, detail))
        sys.exit(1)
    return json.loads(raw) if raw.strip() else None


def same_path(a, b):
    def norm(p):
        return os.path.normcase(os.path.normpath(os.path.expanduser(p)))
    return norm(a) == norm(b)


hub = desired["hub"]
is_hub = not hub_id or call("GET", "/rest/system/status")["myID"] == hub_id

if is_hub:
    say("debug", "this is the hub, {}: it lists no introducer, and its joining service shares the folders".format(hub["name"]))
else:
    want = {"name": hub["name"], "addresses": hub["addresses"], "introducer": True}
    current = call("GET", "/rest/config/devices/" + hub_id)
    if current is None:
        device = call("GET", "/rest/config/defaults/device")
        device.update(want)
        device["deviceID"] = hub_id
        call("POST", "/rest/config/devices", device)
        say("notice", "Syncthing: added {} as this node's introducer, at {}".format(hub["name"], ", ".join(hub["addresses"])))
    else:
        patch = {k: v for k, v in want.items() if current.get(k) != v}
        if patch:
            call("PATCH", "/rest/config/devices/" + hub_id, patch)
            say("notice", "Syncthing: set {} of {}".format(", ".join(sorted(patch)), hub["name"]))
        else:
            say("debug", "Syncthing: {} already set up".format(hub["name"]))

for folder in desired["folders"]:
    folder_id = folder["id"]
    current = call("GET", "/rest/config/folders/" + folder_id)
    if current is None:
        new = call("GET", "/rest/config/defaults/folder")
        new.update({"id": folder_id, "label": folder["label"], "path": folder["path"]})
        devices = [d for d in new.get("devices") or [] if d.get("deviceID")]
        if not is_hub and hub_id not in [d["deviceID"] for d in devices]:
            devices.append({"deviceID": hub_id})
        new["devices"] = devices
        call("POST", "/rest/config/folders", new)
        shared = "" if is_hub else ", shared with " + hub["name"]
        say("notice", "Syncthing: added folder {} at {}{}".format(folder_id, folder["path"], shared))
        continue
    if not same_path(current.get("path", ""), folder["path"]):
        say("warning", "Syncthing: folder {} is at {} here, not {}; its path is left as it is".format(folder_id, current.get("path"), folder["path"]))
    patch = {}
    if current.get("label") != folder["label"]:
        patch["label"] = folder["label"]
    devices = current.get("devices") or []
    if not is_hub and hub_id not in [d.get("deviceID") for d in devices]:
        patch["devices"] = devices + [{"deviceID": hub_id}]
    if patch:
        call("PATCH", "/rest/config/folders/" + folder_id, patch)
        changes = ["shared with " + hub["name"] if k == "devices" else k for k in sorted(patch)]
        say("notice", "Syncthing: folder {}: {}".format(folder_id, ", ".join(changes)))
    else:
        say("debug", "Syncthing: folder {} already set up".format(folder_id))

options = call("GET", "/rest/config/options")
patch = {k: v for k, v in desired["options"].items() if options.get(k) != v}
if patch:
    call("PATCH", "/rest/config/options", patch)
    say("notice", "Syncthing: set {}".format(", ".join("{}={}".format(k, json.dumps(v)) for k, v in sorted(patch.items()))))

if (call("GET", "/rest/config/restart-required") or {}).get("requiresRestart"):
    say("notice", "Syncthing wants a restart to finish applying its configuration")
