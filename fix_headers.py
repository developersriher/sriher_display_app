import os
import re

files_to_update = [
    "lib/views/authentication/add_user_view.dart",
    "lib/views/masters.dart/role.dart",
    "lib/views/masters.dart/device_master.dart",
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/location_master.dart"
]

for file_path in files_to_update:
    if not os.path.exists(file_path):
        print(f"Skipping {file_path}")
        continue
    
    with open(file_path, "r") as f:
        content = f.read()

    # We want to change `constraints.maxWidth <= 1100` to `< 600` ONLY in LayoutBuilders that are for the headers.
    # The table scroll logic uses `> 1100`, `1100.0`. We leave those.
    # We can replace `screenWidth <= 1100` with `screenWidth < 600`.
    # And `constraints.maxWidth <= 1100` with `constraints.maxWidth < 600`.
    # Let's check `isNarrow` / `isMobile` variables.
    
    # Replace screenWidth <= 1100
    content = content.replace("screenWidth <= 1100", "screenWidth < 600")
    content = content.replace("screenWidth < 1100", "screenWidth < 600")
    # Replace constraints.maxWidth <= 1100
    content = content.replace("constraints.maxWidth <= 1100", "constraints.maxWidth < 600")
    
    with open(file_path, "w") as f:
        f.write(content)
    
    print(f"Updated {file_path}")
