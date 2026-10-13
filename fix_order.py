import os
import re

files = [
    "lib/views/authentication/add_user_view.dart",
    "lib/views/masters.dart/role.dart",
    "lib/views/masters.dart/device_master.dart",
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/location_master.dart"
]

for file in files:
    if not os.path.exists(file):
        print(f"File not found: {file}")
        continue
        
    with open(file, 'r') as f:
        content = f.read()

    def replacer(match):
        button_code = match.group(1)
        return f"{button_code},\n                    const SizedBox(height: 10),\n                    showEntries,"

    # In add_user_view.dart
    pattern1 = r"showEntries,\s*const SizedBox\(height: 10\),\s*(if \(addUserBtn != null\) addUserBtn),"
    content = re.sub(pattern1, replacer, content)

    # In others
    pattern2 = r"showEntries,\s*const SizedBox\(height: 10\),\s*(_buildCreate[A-Za-z]+Button\(isNarrow\)),"
    content = re.sub(pattern2, replacer, content)

    with open(file, 'w') as f:
        f.write(content)
    print(f"Reverted order in {file}")

