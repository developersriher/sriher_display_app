import os
import re

files_to_update = [
    "lib/views/template_master.dart/create_template.dart",
    "lib/views/template_master.dart/default_template.dart"
]

def update_file(file_path):
    with open(file_path, "r") as f:
        content = f.read()

    # 1. Update breakpoint to 600
    content = content.replace("screenWidth <= 1100", "screenWidth < 600")

    # 2. Update heading row to include createBtn for desktop
    heading_pattern = r"(\s*)Align\(\s*alignment:\s*isMobile\s*\?\s*Alignment\.center\s*:\s*Alignment\.centerLeft,\s*child:\s*heading,\s*\),"
    heading_replacement = r"""\1isMobile
\1    ? Align(alignment: Alignment.center, child: heading)
\1    : Row(
\1        mainAxisAlignment: MainAxisAlignment.spaceBetween,
\1        children: [heading, createBtn],
\1      ),"""
    
    content = re.sub(heading_pattern, heading_replacement, content)

    # 3. Update the Desktop layout in _buildListHeader / _buildTableControls
    desktop_layout_pattern = r"(:\s*Row\(\s*mainAxisAlignment:\s*MainAxisAlignment\.spaceBetween,\s*crossAxisAlignment:\s*CrossAxisAlignment\.start,\s*children:\s*\[\s*showEntries,\s*Column\(\s*mainAxisSize:\s*MainAxisSize\.min,\s*crossAxisAlignment:\s*CrossAxisAlignment\.end,\s*children:\s*\[\s*if\s*\(createBtn\s*!=\s*null\)\s*createBtn,\s*const\s*SizedBox\(height:\s*10\),\s*searchBox,\s*\],\s*\),\s*\],\s*\);)"
    
    desktop_layout_replacement = r""": Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [showEntries, searchBox],
          );"""
    
    content = re.sub(desktop_layout_pattern, desktop_layout_replacement, content)
    
    with open(file_path, "w") as f:
        f.write(content)
        
    print(f"Updated {file_path}")

for f in files_to_update:
    if os.path.exists(f):
        update_file(f)

