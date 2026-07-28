class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

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
