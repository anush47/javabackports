#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json

def find_gradle_module(repo, filepath):
    """
    Finds the Gradle module path (e.g. :core or :spring-context) for a given file.
    Walks up the directory tree looking for build.gradle.
    """
    # filepath is relative to repo root, e.g. "spring-core/src/test/java/..."
    
    current_dir = os.path.dirname(filepath)
    
    while current_dir:
        # Check if build.gradle exists in this directory
        build_gradle_path = os.path.join(repo, current_dir, "build.gradle")
        
        if os.path.exists(build_gradle_path):
            # Found it!
            normalized_dir = current_dir.replace("\\", "/")
            return ":" + normalized_dir.replace("/", ":")
            
        # Move up one level
        parent = os.path.dirname(current_dir)
        if parent == current_dir: # Safety check
            break
        current_dir = parent
        
    # Check root
    if os.path.exists(os.path.join(repo, "build.gradle")):
        return ":"
        
    return None

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

    lines = output.strip().splitlines()
    
    for line in lines:
        parts = line.split('\t')
        if not parts:
            continue
            
        status = parts[0]
        
        # Handle Renames (R) and Copies (C)
        if status.startswith('R') or status.startswith('C'):
            if len(parts) >= 3:
                filepath = parts[2]
            else:
                continue
        else:
            if len(parts) >= 2:
                filepath = parts[1]
            else:
                continue
        
        # Only process test files
        filename = os.path.basename(filepath)
        is_test_file = (
            "/src/test/" in filepath and 
            (filepath.endswith(".java") or filepath.endswith(".kotlin") or filepath.endswith(".scala") or filepath.endswith(".groovy")) and
            (filename.startswith("Test") or filename.endswith("Test.java") or filename.endswith("Tests.java"))
        )
        
        if not is_test_file:
            continue
            
        # Find the Gradle module
        module_path = find_gradle_module(args.repo, filepath)
        if not module_path:
            continue
            
        if module_path == ":":
            module_path = ""
        
        test_target = ""
        
        try:
            # Extract class name. 
            # Path: spring-core/src/test/java/org/springframework/util/MyTest.java
            # Want: org.springframework.util.MyTest
            
            rel_path = ""
            if "/src/test/java/" in filepath:
                rel_path = filepath.split("/src/test/java/")[1]
            elif "/src/test/kotlin/" in filepath:
                rel_path = filepath.split("/src/test/kotlin/")[1]
            elif "/src/test/groovy/" in filepath:
                rel_path = filepath.split("/src/test/groovy/")[1]
            
            if rel_path:
                class_name = rel_path.replace("/", ".").replace("\\", ".").rsplit(".", 1)[0]
                # Gradle syntax for single test
                test_target = f"{module_path}:test --tests \"{class_name}\""
            else:
                # Fallback to module test if we can't parse the class path
                test_target = f"{module_path}:test"
                
        except IndexError:
            # Fallback
            test_target = f"{module_path}:test"

        if test_target:
            if status == 'A':
                added_tests.add(test_target)
            else:
                modified_tests.add(test_target)

    # Output as JSON
    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
