import 'package:flutter/material.dart';

class SearchableDropdown<T> extends StatefulWidget {
  final String hint;
  final T? value;
  final List<SearchableDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;

  final bool showSearch;
  final double? width;
  final AutovalidateMode? autovalidateMode;
  final String? helperText;

  const SearchableDropdown({
    super.key,
    required this.hint,
    this.value,
    required this.items,
    this.onChanged,
    this.validator,
    this.showSearch = true,
    this.width,
    this.autovalidateMode,
    this.helperText,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class SearchableDropdownItem<T> {
  final T value;
  final String label;

  SearchableDropdownItem({required this.value, required this.label});
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<FormFieldState<T>> _fieldKey = GlobalKey<FormFieldState<T>>();
  bool _isOpen = false;

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fieldKey.currentState?.didChange(widget.value);
      });
    }
    // Check if the items' contents have actually changed
    bool itemsChanged = widget.items.length != oldWidget.items.length;
    if (!itemsChanged) {
      for (int i = 0; i < widget.items.length; i++) {
        if (widget.items[i].value != oldWidget.items[i].value ||
            widget.items[i].label != oldWidget.items[i].label) {
          itemsChanged = true;
          break;
        }
      }
    }
    if (itemsChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _overlayEntry?.markNeedsBuild();
      });
    }
  }

  void _toggleOverlay(FormFieldState<T> state) {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay(state);
    }
  }

  void _showOverlay(FormFieldState<T> state) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _removeOverlay,
            behavior: HitTestBehavior.translucent,
            child: Container(
              color: Colors.transparent,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 5),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Container(
                width: widget.width ?? size.width,
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _DropdownContent<T>(
                  items: widget.items,
                  hint: widget.hint,
                  showSearch: widget.showSearch,
                  onSelected: (val) {
                    state.didChange(val);
                    widget.onChanged?.call(val);
                    _removeOverlay();
                  },
                  selectedValue: widget.value,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    String? displayLabel;
    if (widget.value != null) {
      try {
        displayLabel = widget.items
            .firstWhere((item) => item.value == widget.value)
            .label;
      } catch (_) {}
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: FormField<T>(
        key: _fieldKey,
        validator: widget.validator,
        autovalidateMode: widget.autovalidateMode,
        initialValue: widget.value,
        builder: (FormFieldState<T> state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: widget.onChanged == null ? null : () => _toggleOverlay(state),
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
                    ),
                    errorText: state.errorText,
                    helperText: widget.helperText,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    suffixIcon: Icon(
                      _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: Colors.grey,
                    ),
                  ),
                  child: Text(
                    displayLabel ?? widget.hint,
                    style: TextStyle(
                      fontSize: 13,
                      color: displayLabel != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


class _DropdownContent<T> extends StatefulWidget {
  final List<SearchableDropdownItem<T>> items;
  final String hint;
  final ValueChanged<T> onSelected;
  final T? selectedValue;

  final bool showSearch;

  const _DropdownContent({
    required this.items,
    required this.hint,
    required this.onSelected,
    this.selectedValue,
    this.showSearch = true,
  });

  @override
  State<_DropdownContent<T>> createState() => _DropdownContentState<T>();
}

class _DropdownContentState<T> extends State<_DropdownContent<T>> {
  late List<SearchableDropdownItem<T>> filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
  }

  @override
  void didUpdateWidget(covariant _DropdownContent<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare items to see if the contents are different
    bool itemsChanged = widget.items.length != oldWidget.items.length;
    if (!itemsChanged) {
      for (int i = 0; i < widget.items.length; i++) {
        if (widget.items[i].value != oldWidget.items[i].value ||
            widget.items[i].label != oldWidget.items[i].label) {
          itemsChanged = true;
          break;
        }
      }
    }
    if (itemsChanged) {
      setState(() {
        final query = _searchController.text;
        if (query.isEmpty) {
          filteredItems = widget.items;
        } else {
          filteredItems = widget.items
              .where((item) => item.label
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .toList();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search",
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (query) {
                setState(() {
                  filteredItems = widget.items
                      .where((item) => item.label
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                      .toList();
                });
              },
            ),
          ),
        if (widget.showSearch) const Divider(height: 1),
        Expanded(
          child: filteredItems.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No matches found",
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    bool isSelected = item.value == widget.selectedValue;
                    return ListTile(
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.blue.shade700 : Colors.black87,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: Colors.blue.shade50,
                      onTap: () => widget.onSelected(item.value),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
