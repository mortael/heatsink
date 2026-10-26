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
            result = subprocess.run(command, cwd=project, env=environment, timeout=args.timeout,
                                    check=False, capture_output=True, text=True)
        except subprocess.TimeoutExpired as exc:
            # TimeoutExpired's captured output can come back as bytes even with text=True.
            out = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            err = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
            sys.stdout.write(out)
            sys.stderr.write(err)
            print(f"Test exceeded {args.timeout:g} seconds: {args.scene}", file=sys.stderr)
            return 124
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        # A caught check() failure sets a nonzero exit code itself; an uncaught runtime error
        # (a null reference, a bad cast) does not, so Godot can exit 0 with real bugs logged.
        if result.returncode == 0 and ("SCRIPT ERROR" in result.stdout or "SCRIPT ERROR" in result.stderr):
            print(f"Godot logged a runtime SCRIPT ERROR; treating as a failure: {args.scene}", file=sys.stderr)
            return 1
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
