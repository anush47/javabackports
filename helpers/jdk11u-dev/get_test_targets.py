#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the git repository")
    parser.add_argument("--commit", required=True, help="Commit hash to analyze")
    args = parser.parse_args()
    
    # Get list of changed files
    cmd = ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        print("NONE")
        return
    
    changed_files = output.strip().splitlines()
    test_targets = set()
    
    for f in changed_files:
        f = f.replace("\\", "/")
        
        # Check if it's a test file (contains "test/" in path and ends with .java)
        if "test/" in f and f.endswith(".java"):
            # Add the individual test file instead of the directory
            test_targets.add(f)
    
    # Output
    if not test_targets:
        print("NONE")
    else:
        print(" ".join(sorted(test_targets)))

if __name__ == "__main__":
    main()
