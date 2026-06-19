import 'package:flutter/material.dart';

class ContentLayout {
  const ContentLayout._();

  static const maxWidth = 1040.0;
  static const pagePadding = EdgeInsets.all(20);
  static const sectionGap = SizedBox(height: 14);

  static Widget widthBox({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
