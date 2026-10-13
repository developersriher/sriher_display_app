import glob
import os

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

    # Change constraints.maxWidth <= 1100 to < 600
    content = content.replace("constraints.maxWidth <= 1100", "constraints.maxWidth < 600")
    # Change screenWidth <= 1100 to < 600
    content = content.replace("screenWidth <= 1100", "screenWidth < 600")

    # Reorder the showEntries and the create button
    # Look for the specific column pattern
    import re
    
    # Pattern to match the column children in isNarrow ? SizedBox(...)
    # We want to move showEntries ABOVE the create button
    # In add_user_view:
    #                 if (addUserBtn != null) addUserBtn,
    #                 const SizedBox(height: 10),
    #                 showEntries,
    # In role.dart:
    #                 _buildCreateRoleButton(isNarrow),
    #                 const SizedBox(height: 10),
    #                 showEntries,
    
    def replacer(match):
        button_code = match.group(1)
        return f"showEntries,\n                    const SizedBox(height: 10),\n                    {button_code},"

    pattern1 = r"(if \(addUserBtn != null\) addUserBtn),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern1, replacer, content)

    pattern2 = r"(_buildCreateRoleButton\(isNarrow\)),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern2, replacer, content)

    pattern3 = r"(_buildCreateDeviceButton\(isNarrow\)),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern3, replacer, content)

    pattern4 = r"(_buildCreateDepartmentButton\(isNarrow\)),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern4, replacer, content)

    pattern5 = r"(_buildCreateMappingButton\(isNarrow\)),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern5, replacer, content)

    pattern6 = r"(_buildCreateLocationButton\(isNarrow\)),\s*const SizedBox\(height: 10\),\s*showEntries,"
    content = re.sub(pattern6, replacer, content)

    with open(file, 'w') as f:
        f.write(content)
    print(f"Updated {file}")

