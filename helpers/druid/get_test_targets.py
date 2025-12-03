#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

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
        print(json.dumps({"modified": [], "added": []}))
        return

    modified_tests = set()
    added_tests = set()

    # 2. Analyze changes
    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
            
        status = parts[0]
        f = parts[1]

        # Strict filtering: Only process Test files
        if not f.endswith("Test.java"):
            continue
            
        path_parts = f.split("/")
        if len(path_parts) > 1:
            module = path_parts[0]
            
            # Skip ignored modules
            if module in ["web-console", "distribution", "docs", "examples"]:
                continue
            
            # Check if it's a maven module
            if not os.path.exists(os.path.join(args.repo, module, "pom.xml")):
                continue

            # Extract class name
            # Pattern: [module]/src/test/java/[package]/[Class]Test.java
            if "src/test/java/" in f:
                try:
                    class_path = f.split("src/test/java/")[1]
                    class_name = class_path.replace("/", ".").replace(".java", "")
                    
                    # Target format: module:class
                    target = f"{module}:{class_name}"
                    
                    if status == 'A':
                        added_tests.add(target)
                    else:
                        modified_tests.add(target)
                except:
                    continue

    # 3. Output JSON
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()