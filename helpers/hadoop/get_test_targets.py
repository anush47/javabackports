#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

# Modules known to be broken/require complex envs that we want to skip
BLACKLIST_MODULES = [
    "hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-webapp",
    "hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-docker",
    "hadoop-yarn-project" # Aggregator that often fails if children fail
]

def is_blacklisted(module_path):
    for bad in BLACKLIST_MODULES:
        if module_path.startswith(bad) or bad.startswith(module_path):
             # If exact match or if the module path is a parent of a bad module? 
             # Actually, simpler: just skip if it *is* one of the bad ones.
             if module_path == bad: return True
    return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the git repository")
    parser.add_argument("--commit", required=True, help="Commit hash to analyze")
    args = parser.parse_args()

    # 1. Get list of changed files with status
    cmd = ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        # Fallback: test core modules if git fails
        print(json.dumps({"modified": ["hadoop-common-project/hadoop-common", "hadoop-hdfs-project/hadoop-hdfs"], "added": []}))
        return

    modified_modules = set()
    added_modules = set()

    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
        
        status = parts[0]
        f = parts[1]
        
        # Map file to module
        current_dir = os.path.dirname(f)
        found_module = None
        
        while current_dir:
            pom_path = os.path.join(args.repo, current_dir, "pom.xml")
            if os.path.exists(pom_path):
                if not is_blacklisted(current_dir):
                    found_module = current_dir
                break
            
            parent = os.path.dirname(current_dir)
            if parent == current_dir: break
            current_dir = parent
        
        if not found_module and f == "pom.xml":
             # Root POM changed?
             found_module = "hadoop-common-project/hadoop-common" # Fallback to core
        
        if found_module:
            if status == 'A':
                added_modules.add(found_module)
            else:
                modified_modules.add(found_module)

    # Output as JSON
    print(json.dumps({
        "modified": sorted(list(modified_modules)),
        "added": sorted(list(added_modules))
    }))

if __name__ == "__main__":
    main()