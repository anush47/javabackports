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

    lines = output.strip().splitlines()
    
    for line in lines:
        parts = line.split('\t')
        if not parts:
            continue
            
        status = parts[0]
        
        # Handle Renames (R) and Copies (C) which have 3 parts: status, old_path, new_path
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
        
        # Kafka structure: [module]/src/...
        # e.g. clients/src/test/java/org/apache/kafka/clients/producer/KafkaProducerTest.java
        
        # Only process test files
        filename = os.path.basename(filepath)
        is_test_file = (
            "/src/test/" in filepath and 
            (filepath.endswith(".java") or filepath.endswith(".scala")) and
            (filename.startswith("Test") or filename.endswith("Test.java") or filename.endswith("Tests.java") or filename.endswith("Test.scala") or filename.endswith("Tests.scala"))
        )
        
        if not is_test_file:
            continue
            
        parts_path = filepath.split("/")
        if len(parts_path) < 2:
            continue
            
        module = parts_path[0]
        
        # Verify it is a real module (has build.gradle)
        if not os.path.exists(os.path.join(args.repo, module, "build.gradle")):
            continue

        test_target = ""
        
        try:
            # Extract class name. 
            # Path: clients/src/test/java/org/apache/kafka/clients/MyTest.java
            # Want: org.apache.kafka.clients.MyTest
            
            # Find where package structure starts (after java/ or scala/)
            if "/java/" in filepath:
                rel_path = filepath.split("/java/")[1]
            elif "/scala/" in filepath:
                rel_path = filepath.split("/scala/")[1]
            else:
                # Weird path, fall back to module
                test_target = f":{module}:test"
            
            if not test_target:
                class_name = rel_path.replace("/", ".").rsplit(".", 1)[0]
                # Gradle syntax for single test
                test_target = f":{module}:test --tests \"{class_name}\""
        except IndexError:
            # Fallback
            test_target = f":{module}:test"

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