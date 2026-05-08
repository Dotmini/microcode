import os

for root, _, files in os.walk('CodeTunner'):
    for file in files:
        if file.endswith('.swift'):
            path = os.path.join(root, file)
            with open(path, 'r') as f:
                content = f.read()
            
            if '#Preview' in content:
                # Find the first occurrence of #Preview
                idx = content.find('#Preview')
                if idx != -1:
                    # Strip everything from #Preview to EOF
                    new_content = content[:idx].strip() + '\n'
                    with open(path, 'w') as f:
                        f.write(new_content)
                    print(f"Stripped {path}")
