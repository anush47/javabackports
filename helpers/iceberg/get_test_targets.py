#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os
import json
import re

def find_gradle_module(repo, filepath):
    """
    Finds the Gradle module path for Iceberg's specific structure.
    Based on official Iceberg CI workflows, the pattern is:
    :iceberg-flink:iceberg-flink-{version} (NOT flattened)
    Reference: .github/workflows/flink-ci.yml
    """
    # Normalize path
    normalized = filepath.replace("\\", "/")
    
    # Handle Flink modules: flink/v{version}/flink/ -> :iceberg-flink:iceberg-flink-{version}
    # flink/v{version}/flink-runtime/ -> :iceberg-flink:iceberg-flink-runtime-{version}
    flink_match = re.match(r"flink/v([\d.]+)/(flink|flink-runtime)/", normalized)
    if flink_match:
        version = flink_match.group(1)
        submodule = flink_match.group(2)
        if submodule == "flink":
            return f":iceberg-flink:iceberg-flink-{version}"
        else:  # flink-runtime
            return f":iceberg-flink:iceberg-flink-runtime-{version}"
    
    # Handle Spark modules: spark/v{version}/spark/ -> :iceberg-spark:iceberg-spark-{version}_2.1X
    spark_match = re.match(r"spark/v([\d.]+)/(spark|spark-extensions|spark-runtime)/", normalized)
    if spark_match:
        version = spark_match.group(1)
        submodule = spark_match.group(2)
        # Scala version mapping: 3.x uses 2.12, 4.x uses 2.13
        scala_version = "2.12" if version.startswith("3.") else "2.13"
        return f":iceberg-spark:iceberg-{submodule}-{version}_{scala_version}"
    
    # For other modules, use the standard detection
    # Get the first directory component
    parts = normalized.split("/")
    if len(parts) > 0:
        first_dir = parts[0]
        # Map to iceberg-{modulename} format
        module_names = {
            'api': ':iceberg-api',
            'common': ':iceberg-common',
            'core': ':iceberg-core',
            'data': ':iceberg-data',
            'aliyun': ':iceberg-aliyun',
            'aws': ':iceberg-aws',
            'azure': ':iceberg-azure',
            'orc': ':iceberg-orc',
            'arrow': ':iceberg-arrow',
            'parquet': ':iceberg-parquet',
            'hive-metastore': ':iceberg-hive-metastore',
            'nessie': ':iceberg-nessie',
            'gcp': ':iceberg-gcp',
            'bigquery': ':iceberg-bigquery',
            'dell': ':iceberg-dell',
            'snowflake': ':iceberg-snowflake',
            'delta-lake': ':iceberg-delta-lake',
            'mr': ':iceberg-mr'
        }
        if first_dir in module_names:
            return module_names[first_dir]
    
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

    lines = output.strip().splitlines()
    for line in lines:
        parts = line.split('\t')
        if not parts: continue
        
        status = parts[0]
        if status.startswith('R') or status.startswith('C'):
            filepath = parts[2] if len(parts) >= 3 else None
        else:
            filepath = parts[1] if len(parts) >= 2 else None
            
        if not filepath: continue

        filename = os.path.basename(filepath)
        is_test_file = (
            "/src/test/" in filepath and 
            filepath.endswith(".java") and
            (filename.startswith("Test") or filename.endswith("Test.java") or filename.endswith("Tests.java"))
        )
        
        if not is_test_file:
            continue
            
        module_path = find_gradle_module(args.repo, filepath)
        if not module_path: continue
        
        test_target = ""
        try:
            rel_path = ""
            if "/src/test/java/" in filepath:
                rel_path = filepath.split("/src/test/java/")[1]
            
            if rel_path:
                class_name = rel_path.replace("/", ".").replace("\\", ".").rsplit(".", 1)[0]
                test_target = f"{module_path}:test --tests \"{class_name}\""
            else:
                test_target = f"{module_path}:test"
        except IndexError:
            test_target = f"{module_path}:test"

        if test_target:
            if status == 'A':
                added_tests.add(test_target)
            else:
                modified_tests.add(test_target)

    result = {
        "modified": sorted(list(modified_tests)),
        "added": sorted(list(added_tests))
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
