import os
import sys

def replace_in_file(filepath, replacements):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Skipping {filepath}: {e}")
        return

    new_content = content
    for old, new in replacements.items():
        new_content = new_content.replace(old, new)
        
    if content != new_content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

def main():
    root_dir = '/Users/dotmini/Documents/SX/codetunner-native'
    target_files = [
        'build_distribution.sh',
        'sign_and_notarize.sh',
        '.github/workflows/ci.yml',
        '.github/workflows/release.yml',
        'CodeTunner/SyntaxEngine/SyntaxHighlightingEngine.swift', # Just in case it has mentions
        'generate_checksums.sh',
        'verify_checksums.sh'
    ]
    
    replacements = {
        'CodeTunner': 'MicroCode',
        'codetunner': 'microcode'
    }
    
    for relative_path in target_files:
        full_path = os.path.join(root_dir, relative_path)
        if os.path.exists(full_path):
            replace_in_file(full_path, replacements)
        else:
            print(f"Not found: {full_path}")

if __name__ == '__main__':
    main()
