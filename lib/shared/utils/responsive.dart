import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

enum FormFactor { mobile, tablet, desktop }

FormFactor getFormFactor(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return FormFactor.mobile;
  if (width < Breakpoints.tablet) return FormFactor.tablet;
  return FormFactor.desktop;
}

class ResponsiveHelper {
  static bool isPhone(BuildContext context) => getFormFactor(context) == FormFactor.mobile;
  static bool isTablet(BuildContext context) => getFormFactor(context) == FormFactor.tablet;
  static bool isDesktop(BuildContext context) => getFormFactor(context) == FormFactor.desktop;
  static bool isWide(BuildContext context) => !isPhone(context);

  static double adaptive(double value, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return value * (screenWidth / 375);
  }

  static FormFactor formFactor(BuildContext context) => getFormFactor(context);

  static double avatarSize(BuildContext context) => isPhone(context) ? 36 : 48;

  static double sidePanelWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth * 0.28).clamp(200, 280);
  }

  static double horizontalPadding(BuildContext context) => isPhone(context) ? 12 : 24;

  static double bubbleMaxWidthRatio(BuildContext context) {
    final factor = getFormFactor(context);
    switch (factor) {
      case FormFactor.mobile:
        return 0.97;
      case FormFactor.tablet:
        return 0.85;
      case FormFactor.desktop:
        return 0.75;
    }
  }

  static double codeBlockHeight(BuildContext context) => isPhone(context) ? 120 : 200;

  static double inputMaxHeight(BuildContext context) => isPhone(context) ? 100 : 150;

  static double attachmentPreviewSize(BuildContext context) => isPhone(context) ? 36 : 48;

  static double iconSize(BuildContext context) => isPhone(context) ? 20 : 24;

  static double navIconSize(BuildContext context) => isPhone(context) ? 20 : 24;

  static double navPaddingHorizontal(BuildContext context) => isPhone(context) ? 4 : 8;

  static double navPaddingVertical(BuildContext context) => isPhone(context) ? 4 : 8;

  static double navItemPaddingHorizontal(BuildContext context) => isPhone(context) ? 8 : 12;

  static double navItemPaddingVertical(BuildContext context) => isPhone(context) ? 4 : 8;

  static double navLabelSize(BuildContext context) => isPhone(context) ? 10 : 11;

  static double thumbnailSize(BuildContext context) => isPhone(context) ? 80 : 120;

  static double previewHeight(BuildContext context) => isPhone(context) ? 150 : 200;

  static double listItemSpacing(BuildContext context) => isPhone(context) ? 8 : 12;

  static double cardPadding(BuildContext context) => isPhone(context) ? 12 : 16;

  static double appBarHeight(BuildContext context) => isPhone(context) ? 48 : 56;

  static double mathFontSize(BuildContext context) {
    final factor = getFormFactor(context);
    switch (factor) {
      case FormFactor.mobile:
        return 16.0;
      case FormFactor.tablet:
        return 18.0;
      case FormFactor.desktop:
        return 20.0;
    }
  }

  static double bubblePadding(BuildContext context) => isPhone(context) ? 10 : 14;

  static double fontSize(BuildContext context, {double base = 14}) =>
      base * (isPhone(context) ? 1.0 : 1.15);

  static double inputMinLines(BuildContext context) => isPhone(context) ? 1 : 4;

  static double inputMaxLines(BuildContext context) => isPhone(context) ? 4 : 6;

  static double inputPaddingVertical(BuildContext context) => isPhone(context) ? 10 : 14;

  static double sendButtonSize(BuildContext context) => isPhone(context) ? 56 : 48;

  static double sendButtonIconSize(BuildContext context) => isPhone(context) ? 26 : 22;
}