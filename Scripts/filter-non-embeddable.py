#!/usr/bin/env python3
import json
import os
import sys
import urllib.request
import urllib.parse
from urllib.error import HTTPError, URLError

def main():
    # Parse arguments
    api_key = os.environ.get("YOUTUBE_API_KEY")
    dry_run = False
    catalog_path = None
    
    args = sys.argv[1:]
    
    # Handle --dry-run / -d
    if "--dry-run" in args or "-d" in args:
        dry_run = True
        args = [a for a in args if a not in ("--dry-run", "-d")]
        
    # Handle --file / -f
    if "--file" in args:
        idx = args.index("--file")
        if idx + 1 < len(args):
            catalog_path = args[idx+1]
            args.pop(idx+1)
            args.pop(idx)
        else:
            print("Error: --file option requires a path argument.", file=sys.stderr)
            sys.exit(1)
    elif "-f" in args:
        idx = args.index("-f")
        if idx + 1 < len(args):
            catalog_path = args[idx+1]
            args.pop(idx+1)
            args.pop(idx)
        else:
            print("Error: -f option requires a path argument.", file=sys.stderr)
            sys.exit(1)
            
    if not api_key:
        if len(args) > 0:
            api_key = args[0]
        else:
            print("Error: YouTube API key is required.", file=sys.stderr)
            print("Usage: python3 Scripts/filter-non-embeddable.py [--dry-run] [--file <path_to_catalog>] <YOUTUBE_API_KEY>", file=sys.stderr)
            print("Or set the YOUTUBE_API_KEY environment variable.", file=sys.stderr)
            sys.exit(1)

    # Locate paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    if not catalog_path:
        catalog_path = os.path.join(script_dir, "../web/channels-catalog.json")
    else:
        # Resolve relative to current working directory or absolute
        catalog_path = os.path.abspath(catalog_path)
        
    bump_script_path = os.path.join(script_dir, "bump-catalog-version.py")
    
    if not os.path.exists(catalog_path):
        print(f"Error: Catalog file not found at {catalog_path}", file=sys.stderr)
        sys.exit(1)
        
    with open(catalog_path, "r", encoding="utf-8") as f:
        try:
            catalog = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: failed to parse JSON in {catalog_path}: {e}", file=sys.stderr)
            sys.exit(1)
            
    channels = catalog.get("channels", [])
    if not channels:
        print("No channels found in the catalog.")
        return
        
    # Extract unique YouTube video IDs
    video_ids = []
    video_to_channels = {}
    for ch in channels:
        vid_id = ch.get("youTubeVideoID")
        if vid_id:
            video_ids.append(vid_id)
            if vid_id not in video_to_channels:
                video_to_channels[vid_id] = []
            video_to_channels[vid_id].append(ch)
            
    # Remove duplicates but preserve order if possible
    unique_video_ids = list(dict.fromkeys(video_ids))
    print(f"Checking {len(unique_video_ids)} unique YouTube video IDs in batches of 50 for catalog: {catalog_path}...")
    
    # Batch query YouTube API
    chunk_size = 50
    non_embeddable_ids = {} # maps video_id -> reason
    
    for i in range(0, len(unique_video_ids), chunk_size):
        chunk = unique_video_ids[i:i+chunk_size]
        ids_str = ",".join(chunk)
        
        # Build API request
        url = "https://www.googleapis.com/youtube/v3/videos?" + urllib.parse.urlencode({
            "part": "status,snippet",
            "id": ids_str,
            "key": api_key
        })
        
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TelevistaFilterScript/1.0"})
            with urllib.request.urlopen(req) as response:
                data = json.loads(response.read().decode("utf-8"))
        except HTTPError as e:
            print(f"API HTTP Error ({e.code}): {e.read().decode('utf-8', errors='ignore')}", file=sys.stderr)
            sys.exit(1)
        except URLError as e:
            print(f"Network Error: {e.reason}", file=sys.stderr)
            sys.exit(1)
            
        items = data.get("items", [])
        found_ids_in_chunk = set()
        
        for item in items:
            vid_id = item.get("id")
            found_ids_in_chunk.add(vid_id)
            status = item.get("status", {})
            embeddable = status.get("embeddable", True)
            
            if not embeddable:
                non_embeddable_ids[vid_id] = "Embedding restricted by owner (status.embeddable is false)"
                
        # Check which IDs in this chunk are missing from the response
        for vid_id in chunk:
            if vid_id not in found_ids_in_chunk:
                non_embeddable_ids[vid_id] = "Deleted, private, or invalid video ID (not returned by API)"

    # Filter channels
    filtered_channels = []
    removed_count = 0
    
    for ch in channels:
        vid_id = ch.get("youTubeVideoID")
        if vid_id in non_embeddable_ids:
            reason = non_embeddable_ids[vid_id]
            print(f"Removing channel: '{ch.get('title')}' (ID: {ch.get('id')}, YouTube: {vid_id}) - Reason: {reason}")
            removed_count += 1
        else:
            filtered_channels.append(ch)
            
    if removed_count == 0:
        print("All videos are embeddable and valid. No changes needed.")
        return
        
    print(f"\nSummary: Found {removed_count} non-embeddable/invalid channel(s) out of {len(channels)} total channels.")
    
    if dry_run:
        print("[DRY RUN] Catalog file was not modified.")
        return
        
    # Write back
    catalog["channels"] = filtered_channels
    with open(catalog_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)
        f.write("\n")
        
    print(f"Updated catalog saved to {catalog_path}.")
    
    # Automatically bump the manifest version if bump-catalog-version.py exists AND we updated channels-catalog.json
    if os.path.basename(catalog_path) == "channels-catalog.json" and os.path.exists(bump_script_path):
        print("Running bump-catalog-version.py to increment manifest version...")
        import subprocess
        try:
            subprocess.run([sys.executable, bump_script_path], check=True)
        except subprocess.CalledProcessError as e:
            print(f"Warning: Failed to bump version automatically: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
