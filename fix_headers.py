import re
import os

files = [
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/role.dart",
    "lib/views/masters.dart/location_master.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/device_master.dart"
]

def capitalize_text(match):
    # match.group(1) is the whole text up to the string, match.group(2) is the quote type, match.group(3) is the string content
    return match.group(1) + match.group(2) + match.group(3).upper() + match.group(2)

for filepath in files:
    if not os.path.exists(filepath):
        continue
    with open(filepath, 'r') as f:
        content = f.read()

    # The headers are within a TableRow under `color: Colors.blue.shade50` OR in a headerRow definition.
    # We can locate them by looking for `Text(` followed by `"something"`, and then `style: TextStyle(`
    # containing `fontWeight: FontWeight.bold` and either `Colors.blue` or `Color.fromARGB`.
    
    # Let's write a regex that finds a Text widget that has a TextStyle with FontWeight.bold and a blueish color.
    # It will match:
    # Text(
    #   "...",
    #   ...
    #   style: TextStyle(
    #     color: Colors.blue OR color: Color.fromARGB(255, 33, 150, 243),
    #     fontWeight: FontWeight.bold,
    #     fontSize: 11,
    #   ),
    
    pattern = r'(Text\(\s*)(["\'])(.*?)(["\'])([\s\S]*?style:\s*TextStyle\([\s\S]*?color:\s*)(?:Colors\.blue|Color\.fromARGB\([^)]+\)|Color\.fromRGBO\([^)]+\))([\s\S]*?fontWeight:\s*FontWeight\.bold,\s*fontSize:\s*)\d+(,?\s*\),?)'
    
    # We want to replace it with uppercase text, the new color, and fontSize 14.
    
    def replacement(m):
        prefix = m.group(1)
        quote = m.group(2)
        text = m.group(3).upper()
        mid = m.group(5)
        new_color = 'Color.fromARGB(255, 33, 150, 243)'
        fontWeight_part = m.group(6)
        new_fontSize = '14'
        suffix = m.group(7)
        return f'{prefix}{quote}{text}{quote}{mid}{new_color}{fontWeight_part}{new_fontSize}{suffix}'
        
    new_content = re.sub(pattern, replacement, content)
    
    # Wait, some tables might have the text as a variable, e.g. `titles[index]`.
    # `department.dart` uses `titles[index]`.
    # Let's also match variables like `titles[index]`.
    pattern_var = r'(Text\(\s*)([a-zA-Z0-9_\[\]]+)([\s\S]*?style:\s*const\s*TextStyle\([\s\S]*?color:\s*)(?:Colors\.blue|Color\.fromARGB\([^)]+\)|Color\.fromRGBO\([^)]+\))([\s\S]*?fontWeight:\s*FontWeight\.bold,\s*fontSize:\s*)\d+(,?\s*\),?)'
    
    def replacement_var(m):
        prefix = m.group(1)
        var_name = m.group(2)
        mid = m.group(3)
        new_color = 'Color.fromARGB(255, 33, 150, 243)'
        fontWeight_part = m.group(4)
        new_fontSize = '14'
        suffix = m.group(5)
        return f'{prefix}{var_name}{mid}{new_color}{fontWeight_part}{new_fontSize}{suffix}'
        
    new_content = re.sub(pattern_var, replacement_var, new_content)
    
    # But wait, if they use `titles[index]`, the list of titles is `final titles = ['DEPARTMENT', 'EDIT', 'ACTION', 'DELETE'];`
    # which is already capitalized. We just need the font color and size updated for them.
    # The `replacement_var` does that.
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    print(f"Updated {filepath}")

