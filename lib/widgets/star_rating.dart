import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int value; // 0..5
  final ValueChanged<int> onChanged;
  final double size;
  final Color? color;

  const StarRating({super.key, required this.value, required this.onChanged, this.size = 28, this.color});

  @override
  Widget build(BuildContext context) {
    final active = color ?? Theme.of(context).colorScheme.primary;
    final inactive = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final filled = value >= starIndex;
        return InkWell(
          onTap: () => onChanged(starIndex),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              color: filled ? active : inactive,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}
