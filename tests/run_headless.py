"""Run a Godot test with disposable user data, isolated before autoload startup."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("scene", help="res:// test scene or SceneTree .gd script")
    parser.add_argument("test_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if sys.platform not in {"win32", "linux"}:
        parser.error("User-data isolation is currently supported on Windows and Linux.")
    project = Path(__file__).resolve().parent.parent
    command = [args.godot, "--headless", "--path", str(project), "--fixed-fps", "60"]
    if args.scene.endswith(".gd"):
        command.append("-s")
    command.append(args.scene)
    extra = args.test_args
    if extra[:1] == ["--"]:
        extra = extra[1:]
    if extra:
        command.extend(["--", *extra])
    # Both variables are read by Godot before any project autoload runs.
    # Each invocation, including concurrent CI jobs, gets its own directory.
    with tempfile.TemporaryDirectory(prefix="heatsink-test-") as user_data:
        environment = os.environ.copy()
        environment["APPDATA"] = user_data
        environment["XDG_DATA_HOME"] = user_data
        environment["HEATSINK_TEST_DATA"] = user_data
        try:
            return subprocess.run(command, cwd=project, env=environment,
                                  timeout=args.timeout, check=False).returncode
        except subprocess.TimeoutExpired:
            print(f"Test exceeded {args.timeout:g} seconds: {args.scene}", file=sys.stderr)
            return 124


if __name__ == "__main__":
    raise SystemExit(main())
