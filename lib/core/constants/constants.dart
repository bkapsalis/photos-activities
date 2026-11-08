class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  /// The wide layout's location-chat sidebar needs this much width. Below
  /// it (a tablet held upright, a narrow window) the chats open from a
  /// button in the top bar instead, and the photos get the full width.
  static const double sidebar = 1000;

  /// The wide layout's top bar fits on one row from here. Below it the
  /// categories and the search move to a second row, so nothing ends up
  /// past the edge of the screen.
  static const double oneRowTopBar = 1300;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppSizing {
  static const double mobileBottomNavHeight = 80;
  static const double webTopNavHeight = 64;
  static const double webSidebarWidth = 280;
  static const double chatPanelWidth = 360;
  static const double avatarSmall = 32;
  static const double avatarMedium = 40;
  static const double avatarLarge = 48;
}
