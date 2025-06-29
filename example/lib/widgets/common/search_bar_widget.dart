import 'package:flutter/material.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearch;
  final VoidCallback onClear;
  final String hintText;

  const SearchBarWidget({
    Key? key,
    required this.controller,
    required this.onSearch,
    required this.onClear,
    this.hintText = 'Search models (GGUF, TFLite, gemma, llama, phi)...',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.search_rounded,
              color: Theme.of(context).primaryColor,
              size: 18,
            ),
          ),
          suffixIcon:
              controller.text.isNotEmpty
                  ? IconButton(
                    onPressed: () {
                      controller.clear();
                      onClear();
                    },
                    icon: Icon(
                      Icons.clear_rounded,
                      color: Colors.grey.shade600,
                      size: 18,
                    ),
                  )
                  : IconButton(
                    onPressed: () => onSearch(controller.text),
                    icon: Icon(
                      Icons.tune_rounded,
                      color: Theme.of(context).primaryColor,
                      size: 18,
                    ),
                  ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (value) {},
        onSubmitted: onSearch,
      ),
    );
  }
}
