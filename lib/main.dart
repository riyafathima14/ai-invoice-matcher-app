import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_preview/device_preview.dart';
import 'package:invoice_matcher/screens/splash_screen.dart'; 

void main() {
  runApp(
    DevicePreview(
      enabled: !const bool.fromEnvironment('dart.vm.product'),
      builder: (context) => const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryLight = Color(0xFF204ECF);
    const Color onPrimaryLight = Color(0xFFFFFFFF);
    const Color backgroundLight = Color(0xFFF0F2F5);
    const Color surfaceLight = Color(0xFFFFFFFF);
    const Color onSurfaceLight = Color(0xFF1E2749);

    const Color primaryDark = Color(0xFF71A0FF);
    const Color onPrimaryDark = Color(0xFF000000);
    const Color backgroundDark = Color(0xFF121212);
    const Color surfaceDark = Color(0xFF1E1E1E);
    const Color onSurfaceDark = Color(0xFFE0E0E0);

    return MaterialApp(
      title: 'Invoice Matcher',
      debugShowCheckedModeBanner: false,
      locale: DevicePreview.locale(context), 
      builder: DevicePreview.appBuilder, 
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundLight,
        colorScheme: const ColorScheme.light(
          primary: primaryLight,
          onPrimary: onPrimaryLight,
          background: backgroundLight,
          surface: surfaceLight,
          onSurface: onSurfaceLight,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: onSurfaceLight,
            displayColor: onSurfaceLight,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceLight,
          foregroundColor: onSurfaceLight,
          elevation: 0,
        ),
      ),

      // Dark Theme
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: primaryDark,
          onPrimary: onPrimaryDark,
          background: backgroundDark,
          surface: surfaceDark,
          onSurface: onSurfaceDark,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: onSurfaceDark,
            displayColor: onSurfaceDark,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceDark,
          foregroundColor: onSurfaceDark,
          elevation: 0,
        ),
      ),

      themeMode: ThemeMode.system, 

      home: const SplashScreen(),
    );
  }
}
