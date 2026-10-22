import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../services/firestore_service.dart';

/// The longest place name or region the rules accept (newPhoto and
/// ownerDetailsEdit in firestore.rules). Typing stops there rather than
/// letting an upload be refused at the end.
const maxPlaceNameLength = 100;
final placeNameLimit = [LengthLimitingTextInputFormatter(maxPlaceNameLength)];

/// Margins around the app's form dialogs. Material's default leaves 40
/// points each side, which on a phone with a large display size (a Pixel 7
/// Pro set to a bigger "Display size" is about 345 points wide) left the
/// forms about 217 points of room — too little for a title beside its close
/// button, or "Museums - Historic Sites" in a dropdown.
const dialogInsetPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 24);

class UserAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;

  const UserAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class LocationPill extends StatelessWidget {
  final String locationName;
  final bool showDot;

  const LocationPill({
    super.key,
    required this.locationName,
    this.showDot = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.pillBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.pillDot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              locationName,
              style: const TextStyle(
                color: AppColors.pillText,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class HeartCount extends StatelessWidget {
  final int count;
  final double iconSize;
  final Color? color;

  const HeartCount({
    super.key,
    required this.count,
    this.iconSize = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.favorite,
          size: iconSize,
          color: color ?? AppColors.heartRed,
        ),
        const SizedBox(width: 3),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: iconSize * 0.8,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Location name entry field that offers previously-used location names
/// (subcategories within the selected category) as a dropdown, with an
/// option to enter a brand new one.
class LocationNameField extends StatefulWidget {
  final String category;
  final TextEditingController controller;
  final FirestoreService firestoreService;
  final bool isDense;

  const LocationNameField({
    super.key,
    required this.category,
    required this.controller,
    required this.firestoreService,
    this.isDense = false,
  });

  @override
  State<LocationNameField> createState() => _LocationNameFieldState();
}

class _LocationNameFieldState extends State<LocationNameField> {
  static const _addNewValue = '__add_new_location__';

  bool _isNewEntry = false;

  @override
  void didUpdateWidget(covariant LocationNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      // Locations are scoped to category, so switching category invalidates
      // whatever was picked/typed before.
      _isNewEntry = false;
      widget.controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: widget.firestoreService.streamDistinctLocations(widget.category),
      builder: (context, snapshot) {
        final locations = snapshot.data ?? const <String>[];

        if (_isNewEntry || locations.isEmpty) {
          return TextFormField(
            controller: widget.controller,
            inputFormatters: placeNameLimit,
            decoration: InputDecoration(
              labelText: 'Location Name',
              hintText: 'e.g. Vasona Lake, Almaden Lake',
              border: const OutlineInputBorder(),
              isDense: widget.isDense,
              suffixIcon: locations.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.list),
                      tooltip: 'Choose an existing location',
                      onPressed: () => setState(() => _isNewEntry = false),
                    )
                  : null,
            ),
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Please enter a location name'
                : null,
          );
        }

        final currentValue = locations.contains(widget.controller.text)
            ? widget.controller.text
            : null;

        return DropdownButtonFormField<String>(
          initialValue: currentValue,
          // Fit the field and cut long names short, rather than overflow it.
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Location Name',
            hintText: 'Select a location',
            border: const OutlineInputBorder(),
            isDense: widget.isDense,
          ),
          items: [
            ...locations.map(
              (loc) => DropdownMenuItem(
                value: loc,
                child: Text(loc, overflow: TextOverflow.ellipsis),
              ),
            ),
            const DropdownMenuItem(
              value: _addNewValue,
              child: Text('+ Add new location'),
            ),
          ],
          validator: (val) => (val == null || val.isEmpty)
              ? 'Please select or add a location'
              : null,
          onChanged: (val) {
            if (val == _addNewValue) {
              setState(() => _isNewEntry = true);
              widget.controller.clear();
            } else if (val != null) {
              setState(() => widget.controller.text = val);
            }
          },
        );
      },
    );
  }
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileLayout;
  final Widget webLayout;
  final double breakpoint;

  const ResponsiveLayout({
    super.key,
    required this.mobileLayout,
    required this.webLayout,
    this.breakpoint = 600,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return webLayout;
        }
        return mobileLayout;
      },
    );
  }
}

class CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
