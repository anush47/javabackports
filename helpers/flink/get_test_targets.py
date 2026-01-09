#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json


def find_module_for_file(repo, filepath):
    """Find the Maven module (directory with pom.xml) for a given file."""
    current_dir = os.path.dirname(filepath) if filepath else ""

    while current_dir:
        pom_path = os.path.join(repo, current_dir, "pom.xml")
        if os.path.exists(pom_path):
            return current_dir
        parent = os.path.dirname(current_dir)
        if parent == current_dir:
            break
        current_dir = parent

    return None


def extract_test_class(filepath):
    """Extract the fully qualified test class name from a test file path."""
    if "/src/test/java/" not in filepath:
        return None

    try:
        class_part = filepath.split("/src/test/java/")[1]
        class_name = class_part.replace("/", ".").replace(".java", "")
        return class_name
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the git repository")
    parser.add_argument("--commit", required=True, help="Commit hash to analyze")
    args = parser.parse_args()

    cmd = ["git", "diff-tree", "--no-commit-id", "--name-status", "-r", args.commit]
    try:
        output = subprocess.check_output(cmd, cwd=args.repo, text=True)
    except subprocess.CalledProcessError:
        print(json.dumps({"modified": [], "added": []}))
        return

    modified_tests = set()
    added_tests = set()

    for line in output.strip().splitlines():
        parts = line.split("\t")
        if not parts:
            continue

        status = parts[0]

        # Handle Renames (R) and Copies (C)
        if status.startswith("R") or status.startswith("C"):
            if len(parts) >= 3:
                filepath = parts[2]
            else:
                continue
        else:
            if len(parts) >= 2:
                filepath = parts[1]
            else:
                continue

        filename = os.path.basename(filepath)

        is_test_file = (
            "/src/test/java/" in filepath
            and filepath.endswith(".java")
            and (
                filename.startswith("Test")
                or filename.endswith("Test.java")
                or filename.endswith("Tests.java")
                or filename.endswith("IT.java")
            )
        )

        if not is_test_file:
            continue

        module = find_module_for_file(args.repo, filepath)
        if not module:
            continue

        class_name = extract_test_class(filepath)
        if not class_name:
            test_target = module
        else:
            test_target = f"{module}:{class_name}"

        if status == "A":
            added_tests.add(test_target)
        else:
            modified_tests.add(test_target)

    result = {
        "modified": sorted(modified_tests),
        "added": sorted(added_tests),
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
