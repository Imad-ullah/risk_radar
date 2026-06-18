import 'package:flutter/material.dart';

class R {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double blockH;
  static late double blockV;

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    blockH = screenWidth / 100;
    blockV = screenHeight / 100;
  }
}
