import os

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
    
    replacements = {
        'CodeTunner': 'MicroCode',
        'codetunner': 'microcode',
        'CodeTunnerCore': 'MicrocodeCore',
        'CodeTunnerKernel': 'MicroCodeKernel',
        'CodeTunnerSupport': 'MicroCodeSupport',
        'codetunner-native': 'codetunner-native' # ensure we don't mess up the root dir path
    }

    for dirpath, dnames, fnames in os.walk(root_dir):
        # skip .git and build directories
        if '.git' in dirpath or '.build' in dirpath or 'build' in dirpath or 'Dist' in dirpath or 'target' in dirpath:
            continue
            
        for f in fnames:
            if f.endswith('.rs'):
                full_path = os.path.join(dirpath, f)
                replace_in_file(full_path, replacements)

if __name__ == '__main__':
    main()
