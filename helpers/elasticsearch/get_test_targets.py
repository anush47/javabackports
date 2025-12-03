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

    # Get list of changed files with status (A=added, M=modified, D=deleted)
    cmd = ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        print(json.dumps({"modified": [], "added": []}))
        return

    modified_tests = set()
    added_tests = set()

    for line in output.strip().splitlines():
        parts = line.split('\t', 1)
        if len(parts) != 2:
            continue
            
        status = parts[0]
        f = parts[1]
        
        # Only process test files
        if not (f.endswith("Tests.java") or f.endswith("IT.java")):
            continue
        
        # Find the Gradle module for this file
        head = f
        module_path = ""
        while head:
            head, tail = os.path.split(head)
            if os.path.exists(os.path.join(args.repo, head, "build.gradle")):
                if head == "":
                    module_path = ""
                else:
                    module_path = ":" + head.replace("/", ":")
                break
        
        # Skip if we couldn't find a module
        if module_path == "" and "build.gradle" not in f:
            continue
        
        # Extract test class name
        try:
            if "src/test/java/" in f:
                class_path = f.split("src/test/java/")[1]
                class_name = class_path.replace("/", ".").replace(".java", "")
                test_target = f"{module_path}:test --tests \"{class_name}\""
            elif "src/yamlRestTest/java/" in f:
                test_target = f"{module_path}:test"
            else:
                test_target = f"{module_path}:test"
            
            # Categorize by status
            if status == 'M':
                modified_tests.add(test_target)
            elif status == 'A':
                added_tests.add(test_target)
        except:
            continue
    
    # Output as JSON with separate lists
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()