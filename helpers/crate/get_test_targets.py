#!/usr/bin/env python3
"""
Extract Maven test targets for CrateDB modified test files.
"""

import sys
import os
import xml.etree.ElementTree as ET


def find_module_for_file(file_path, repo_dir):
    """Find the Maven module containing the given file."""
    # Navigate up from the file to find pom.xml
    current_dir = os.path.dirname(os.path.join(repo_dir, file_path))
    
    while current_dir.startswith(repo_dir):
        pom_path = os.path.join(current_dir, 'pom.xml')
        if os.path.exists(pom_path):
            # Found a module with pom.xml
            # Get relative path from repo root
            module_path = os.path.relpath(current_dir, repo_dir)
            if module_path == '.':
                return None  # Root module
            return module_path
        
        parent_dir = os.path.dirname(current_dir)
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
    
    return None


def extract_test_class_name(file_path):
    """Extract the test class name from the Java file path."""
    # Get filename without .java extension
    filename = os.path.basename(file_path)
    if filename.endswith('.java'):
        return filename[:-5]
    return filename


def main():
    if len(sys.argv) < 3:
        print("Usage: get_test_targets.py <repo_dir> <test_file1> [test_file2] ...")
        sys.exit(1)
    
    repo_dir = sys.argv[1]
    test_files = sys.argv[2:]
    
    test_targets = []
    
    for test_file in test_files:
        module = find_module_for_file(test_file, repo_dir)
        test_class = extract_test_class_name(test_file)
        
        if module:
            # Maven format: -pl module -Dtest=TestClass
            target = f"-pl {module} -Dtest={test_class} test"
        else:
            # Root level test
            target = f"-Dtest={test_class} test"
        
        test_targets.append(target)
    
    # Print targets space-separated
    print(" ".join(test_targets))


if __name__ == '__main__':
    main()
