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
        lines = f.readlines()
        
    new_lines = []
    
    for i, line in enumerate(lines):
        context = "".join(lines[max(0, i-6):min(len(lines), i+6)])
        
        # 1. Top Heading size 16
        # Screen Title (e.g. "Department List")
        if re.search(r'fontSize:\s*22', line):
            if 'List"' in context or "List'" in context or 'Master"' in context:
                line = re.sub(r'fontSize:\s*22', 'fontSize: 16', line)
                
        # Dialog Title (StylishDialog)
        if 'titleStyle:' in context and 'StylishDialog' in context:
            line = re.sub(r'fontSize:\s*(isMobile\s*\?\s*\d+\s*:\s*\d+|\d+)', 'fontSize: 16', line)
        elif 'titleStyle:' in "".join(lines[max(0, i-3):min(len(lines), i+3)]):
            line = re.sub(r'fontSize:\s*(isMobile\s*\?\s*\d+\s*:\s*\d+|\d+)', 'fontSize: 16', line)
            
        # 2. Table Headers (size 14, uppercase, color Color.fromARGB(255, 33, 150, 243))
        # Identify them by checking if it's within a TableRow or _getColumns with blueish color and bold text
        # They usually have `color: Colors.blue` or `Color.fromARGB(255, 33, 150, 243)` and `fontWeight: FontWeight.bold`
        # And they are a Text widget.
        
        # Let's fix the header styling on the lines that contain colors or Text inside headers.
        is_table_header_context = ('FontWeight.bold' in context or 'fontWeight: FontWeight.bold' in context) and \
                                  ('Colors.blue' in context or 'Color.fromARGB' in context or 'Color.fromRGBO(33, 150, 243' in context) and \
                                  ('titleStyle' not in context and 'AnimatedHeading' not in context and 'List"' not in context and 'Master"' not in context)
                                  
        # Actually, "No matching roles found" is also blue + bold + size 13.
        # "No matching" -> exclude this.
        if 'No matching' in context:
            is_table_header_context = False
            
        if is_table_header_context and re.search(r'fontSize:\s*\d+', line):
            line = re.sub(r'fontSize:\s*\d+', 'fontSize: 14', line)
            
        if is_table_header_context and re.search(r'color:\s*(?:Colors\.blue|Color\.fromRGBO\([^)]+\)|Color\.fromARGB\([^)]+\))', line):
            line = re.sub(r'color:\s*(?:Colors\.blue|Color\.fromRGBO\([^)]+\)|Color\.fromARGB\([^)]+\))', 'color: Color.fromARGB(255, 33, 150, 243)', line)

        # To uppercase the text in table headers:
        # The text is usually `Text("Role",` or `Text('Role',`
        if is_table_header_context and re.search(r'Text\(\s*(["\'])(.*?)\1', line):
            def upper_repl(m):
                # Don't uppercase "#" or empty
                return f'Text({m.group(1)}{m.group(2).upper()}{m.group(1)}'
            line = re.sub(r'Text\(\s*(["\'])(.*?)\1', upper_repl, line)
            
        # If they use `titles[index]` in _getColumns
        if is_table_header_context and re.search(r'titles\[index\]', line):
            # It's already uppercase in the titles list!
            pass
            
        # 3. Data in table below headers and outside table: size 12
        # If it's a fontSize line, and it's not a heading or table header, change to 12
        if re.search(r'fontSize:\s*(isMobile\s*\?\s*\d+\s*:\s*\d+|\d+)', line) and not is_table_header_context:
            # Skip if it's AnimatedHeading / Screen title / Dialog title (handled above and they have 16)
            if 'fontSize: 16' not in line:
                # Replace with 12
                line = re.sub(r'fontSize:\s*(isMobile\s*\?\s*\d+\s*:\s*\d+|\d+)', 'fontSize: 12', line)
                
        new_lines.append(line)
        
    with open(filepath, 'w') as f:
        f.writelines(new_lines)
    print(f"Updated {filepath}")

