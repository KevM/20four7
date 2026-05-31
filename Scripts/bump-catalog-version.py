#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone

def main():
    # Locate the manifest file relative to the script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    manifest_path = os.path.join(script_dir, "../web/channels-manifest.json")
    
    if not os.path.exists(manifest_path):
        print(f"Error: manifest file not found at {manifest_path}", file=sys.stderr)
        sys.exit(1)
        
    with open(manifest_path, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: failed to parse JSON in {manifest_path}: {e}", file=sys.stderr)
            sys.exit(1)
        
    # Increment catalogVersion
    old_version = manifest.get("catalogVersion", 0)
    new_version = old_version + 1
    manifest["catalogVersion"] = new_version
    
    # Update publishedAt to current UTC time
    now_utc = datetime.now(timezone.utc)
    # Format: YYYY-MM-DDTHH:MM:SSZ
    manifest["publishedAt"] = now_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n") # Add trailing newline
        
    print(f"Successfully bumped catalog version from {old_version} to {new_version} and updated publishedAt to {manifest['publishedAt']}")

if __name__ == "__main__":
    main()
