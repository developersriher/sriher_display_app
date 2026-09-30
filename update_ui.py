import os
import re

files = [
    "lib/views/masters.dart/department.dart",
    "lib/views/masters.dart/location_master.dart",
    "lib/views/masters.dart/device_master.dart",
    "lib/views/masters.dart/mapping.dart",
    "lib/views/masters.dart/role.dart",
]

for filepath in files:
    if not os.path.exists(filepath): continue
    with open(filepath, 'r') as f:
        content = f.read()

    # Add dart:ui import
    if "import 'dart:ui';" not in content:
        content = re.sub(r"(import 'package:flutter/material.dart';)", r"\1\nimport 'dart:ui';", content)
    
    # 1. Update Layout of Tables to use LayoutBuilder and PointerDeviceKind
    # Find `SingleChildScrollView( child: Container( width: double.infinity,`
    table_regex = r'(SingleChildScrollView\(\s*child:\s*Container\(\s*width:\s*double\.infinity,\s*decoration:\s*BoxDecoration\()'
    if re.search(table_regex, content):
        table_repl = r'''LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;
                    final double tableWidth = isDesktop ? constraints.maxWidth : 900.0;
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: tableWidth),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: Container(
                                width: tableWidth,
                                decoration: BoxDecoration('''
        
        content = re.sub(table_regex, table_repl, content)
        
        # We need to add the closing brackets for LayoutBuilder, ScrollConfiguration, Scrollbar, ConstrainedBox, etc.
        # But wait, replacing `SingleChildScrollView( child: Container( ...` with 5 wrappers means we need to add 5 closing brackets where it used to be just 1.
        # Let's fix this in a simpler way.

