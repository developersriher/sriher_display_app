import glob
import re

files = [
    "lib/views/authentication/add_user_view.dart",
    "lib/views/masters.dart/role.dart",
    "lib/views/masters.dart/device_master.dart",
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/location_master.dart",
    "lib/views/template_master.dart/create_template.dart",
    "lib/views/template_master.dart/default_template.dart"
]

for file in files:
    with open(file, 'r') as f:
        content = f.read()
    
    # Find the table header row
    headers = re.findall(r'"([A-Z\s#]+)"\s*,\s*style:\s*(?:const\s+)?TextStyle', content)
    if not headers:
        # fallback
        headers = re.findall(r'Text\(\s*"([A-Z\s#]+)"', content)
    print(f"{file}: {list(dict.fromkeys(headers))}")

