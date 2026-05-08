#!/usr/bin/env python3
"""
Replace #Preview { ... } with _Previews_: PreviewProvider pattern for SPM compatibility.
The #Preview macro requires Xcode's PreviewsMacros which isn't available in SPM builds.
Solution: Convert to PreviewProvider which works in both Xcode and SPM.
"""
import os
import re

count = 0
for root, _, files in os.walk('CodeTunner'):
    for file in files:
        if not file.endswith('.swift'):
            continue
        path = os.path.join(root, file)
        with open(path, 'r') as f:
            lines = f.readlines()
        
        content = ''.join(lines)
        if '#Preview' not in content:
            continue
        
        # Find the line number where #Preview starts (0-based)
        preview_start = None
        for i, line in enumerate(lines):
            if line.strip().startswith('#Preview'):
                preview_start = i
                break
        
        if preview_start is None:
            continue
        
        # Extract the preview body (find matching braces)
        brace_count = 0
        preview_end = None
        body_lines = []
        in_body = False
        
        for i in range(preview_start, len(lines)):
            line = lines[i]
            for ch in line:
                if ch == '{':
                    brace_count += 1
                    if brace_count == 1:
                        in_body = True
                elif ch == '}':
                    brace_count -= 1
                    if brace_count == 0:
                        preview_end = i
                        break
            
            if in_body and preview_end is None:
                # Collect body lines (skip the #Preview { line itself for first line)
                if i == preview_start:
                    # Extract content after the opening brace
                    after_brace = line.split('{', 1)[1] if '{' in line else ''
                    if after_brace.strip():
                        body_lines.append('            ' + after_brace.strip() + '\n')
                else:
                    body_lines.append(line)
            elif preview_end is not None:
                # Last line - extract content before closing brace
                if i == preview_start:
                    # Single line preview
                    between = line.split('{', 1)[1].rsplit('}', 1)[0]
                    if between.strip():
                        body_lines.append('            ' + between.strip() + '\n')
                else:
                    before_close = line.rsplit('}', 1)[0]
                    if before_close.strip():
                        body_lines.append(before_close)
                break
        
        if preview_end is None:
            print(f"WARNING: Could not find matching brace in {path}")
            continue
        
        # Build the replacement using a unique struct name based on filename
        struct_name = file.replace('.swift', '').replace(' ', '_') + '_Previews'
        
        # Clean body lines - ensure proper indentation
        clean_body = []
        for bl in body_lines:
            stripped = bl.rstrip('\n').rstrip()
            if stripped:
                # Ensure 12-space indentation (3 levels: struct > static > body)
                clean = stripped.lstrip()
                clean_body.append('            ' + clean)
        
        body_str = '\n'.join(clean_body) if clean_body else '            EmptyView()'
        
        replacement = f'''struct {struct_name}: PreviewProvider {{
    static var previews: some View {{
{body_str}
    }}
}}
'''
        
        # Replace in the file
        new_lines = lines[:preview_start] + [replacement]
        # Skip any remaining content after the preview block (should be just whitespace/EOF)
        remaining = lines[preview_end + 1:]
        new_lines.extend(remaining)
        
        with open(path, 'w') as f:
            f.writelines(new_lines)
        count += 1
        print(f"Fixed {path}")

print(f"\nDone! Fixed {count} files.")
