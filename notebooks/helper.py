import subprocess
import os

def source_env(script_path):
    """Source a shell script and import its env vars into the current Python process."""
    result = subprocess.run(
        ["bash", "-c", f"source {script_path} && env"],
        capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            os.environ[key] = value

