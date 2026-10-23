#!/usr/bin/env python3
"""Local command doubles: no network, Docker daemon, or Git writes."""

import json
import os
import sys
from pathlib import Path

state_path = Path(os.environ["CI_TEST_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
command = Path(sys.argv[0]).name


def save() -> None:
    state_path.write_text(json.dumps(state))


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def value(flag: str, default: str = "") -> str:
    return args[args.index(flag) + 1] if flag in args else default


if command == "git":
    print(state["head"] + "\trefs/heads/master")
elif command == "docker":
    if args[:3] == ["buildx", "imagetools", "inspect"]:
        ref = args[3]
        if ref in state.get("errors", []):
            fail("registry connection refused")
        digest = state["tags"].get(ref)
        if "@" in ref:
            digest = ref.split("@")[1]
        if not digest:
            fail("manifest unknown")
        if "--raw" in args:
            if ref.startswith("alpine@"):
                print(json.dumps(state["alpine_index"]))
            else:
                print(
                    json.dumps(
                        {
                            "manifests": [
                                {
                                    "platform": {
                                        "os": "linux",
                                        "architecture": "amd64",
                                    },
                                    "digest": digest,
                                }
                            ]
                        }
                    )
                )
        elif value("--format") == "{{json .Image}}":
            print(json.dumps({"config": {"Labels": state["labels"][digest]}}))
        else:
            print(digest)
    elif args[:3] == ["buildx", "imagetools", "create"]:
        target = value("--tag")
        if target in state.get("publish_errors", []):
            fail("simulated publish interruption")
        state["tags"][target] = args[-1].split("@")[1]
        state.setdefault("writes", []).append(target)
        save()
    else:
        fail("Unexpected Docker command: " + repr(args))
elif command == "curl":
    url = next(arg for arg in args if arg.startswith("https://"))
    if state.get("api_error"):
        fail("API unavailable")
    if state.get("forbid_gitlab") and url.startswith("https://gitlab.invalid"):
        fail("Local check must not contact GitLab")
    method = value("--request", "GET")
    if method != "GET":
        state.setdefault("api_writes", []).append({"url": url, "args": args})
        if url.endswith("/repository/commits"):
            payload = json.loads(value("--data"))
            for action in payload["actions"]:
                state["files"][action["file_path"]] = action["content"]
        save()
        print(json.dumps({"iid": 1, "web_url": "https://gitlab.invalid/mr/1"}))
    elif "/repository/branches/" in url:
        if "--write-out" in args:
            print(state.get("branch_status", "404"))
        else:
            print(json.dumps({"commit": {"id": state["head"]}}))
    elif "/repository/files/" in url:
        name = url.split("/repository/files/")[1].split("/raw")[0]
        print(state["files"][name])
    elif url.endswith("/merge_requests"):
        print(json.dumps([{"iid": 1}] if state.get("open_mr") else []))
    elif url == "https://pypi.org/pypi/ansible/json":
        print(json.dumps({"info": {"version": state.get("ansible_latest", "14.6.0")}}))
    elif url.startswith("https://pypi.org/pypi/ansible/"):
        print(json.dumps({"info": {"requires_dist": ["ansible-core~=2.21.0"]}}))
    else:
        fail("Unexpected API request: " + url)
else:
    fail("Unexpected tool: " + command)
