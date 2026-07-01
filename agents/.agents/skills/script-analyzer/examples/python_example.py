#!/usr/bin/env python3
"""Example Python script with various operations"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import requests


def download_file(url, destination):
    """Download a file from URL"""
    response = requests.get(url)
    with open(destination, "wb") as f:
        f.write(response.content)


def cleanup_temp():
    """Clean up temporary files"""
    temp_dir = Path("/tmp/myapp")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)


def install_package(package):
    """Install a Python package"""
    subprocess.run([sys.executable, "-m", "pip", "install", package], check=True)


def modify_config():
    """Modify application configuration"""
    config_path = Path.home() / ".config" / "myapp" / "config.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)

    config = {"api_key": "your-api-key-here", "debug": True, "log_level": "INFO"}

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)


def main():
    # Download some data
    download_file("https://example.com/data.csv", "/tmp/data.csv")

    # Install dependencies
    install_package("pandas")
    install_package("numpy")

    # Modify configuration
    modify_config()

    # Run system command
    os.system('echo "Hello from Python script"')

    # Clean up
    cleanup_temp()

    print("Script completed successfully!")


if __name__ == "__main__":
    main()
