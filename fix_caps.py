import re
import os

files = [
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/role.dart",
    "lib/views/masters.dart/location_master.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/device_master.dart"
]

for filepath in files:
    if not os.path.exists(filepath):
        continue
    with open(filepath, 'r') as f:
        content = f.read()

    # Pattern to match:
    # Text(
    #   "Role",
    #   style: TextStyle(
    #     color: Color.fromARGB(255, 33, 150, 243),
    #     fontWeight: FontWeight.bold,
    #     fontSize: 14,
    
    # We want to match: `Text(` optional spaces/newlines `"` or `'` some text `"` or `'` optional spaces/newlines `style: TextStyle(` optional spaces/newlines `color: Color.fromARGB`
    
    pattern = r'(Text\(\s*)(["\'])(.*?)(["\'])([\s\S]*?style:\s*const\s*TextStyle\([\s\S]*?color:\s*Color\.fromARGB\([^)]+\)[\s\S]*?fontWeight:\s*FontWeight\.bold,\s*fontSize:\s*14)'
    pattern2 = r'(Text\(\s*)(["\'])(.*?)(["\'])([\s\S]*?style:\s*TextStyle\([\s\S]*?color:\s*Color\.fromARGB\([^)]+\)[\s\S]*?fontWeight:\s*FontWeight\.bold,\s*fontSize:\s*14)'
    
    def repl(m):
        return m.group(1) + m.group(2) + m.group(3).upper() + m.group(4) + m.group(5)
        
    new_content = re.sub(pattern, repl, content)
    new_content = re.sub(pattern2, repl, new_content)
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    print(f"Updated {filepath}")

