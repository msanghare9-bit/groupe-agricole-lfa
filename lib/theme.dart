import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Couleurs du logo LFARM.
class Lf {
  static const vert = Color(0xFF2F6B3F);
  static const feuille = Color(0xFF3E8A55);
  static const vertClair = Color(0xFFEEF4EC);
  static const orange = Color(0xFFE28A2B);
  static const orangeFonce = Color(0xFFB5620F);
  static const orangeClair = Color(0xFFFDF0E1);
  static const rouge = Color(0xFFC2412D);
  static const rougeClair = Color(0xFFFBE7E3);
  static const creme = Color(0xFFF7F4EC);
  static const sable = Color(0xFFF1ECE2);
  static const taupe = Color(0xFFA39782);
  static const brun = Color(0xFF7A6A4F);
  static const encre = Color(0xFF2B2A26);
  static const bord = Color(0xFFECE6D8);

  static TextStyle serif({double size = 18, Color color = encre, FontWeight weight = FontWeight.w500, FontStyle? style}) =>
      GoogleFonts.lora(fontSize: size, color: color, fontWeight: weight, fontStyle: style);

  static const devise = "Oasis d'essai du Lycée Franco-Arabe de Kébémer";
}

ThemeData themeLfarm() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  final schema = ColorScheme.fromSeed(seedColor: Lf.vert).copyWith(
    primary: Lf.vert,
    onPrimary: Colors.white,
    primaryContainer: Lf.vertClair,
    onPrimaryContainer: Lf.vert,
    secondary: Lf.orange,
    onSecondary: Colors.white,
    secondaryContainer: Lf.orangeClair,
    onSecondaryContainer: Lf.orangeFonce,
    tertiaryContainer: Lf.sable,
    onTertiaryContainer: Lf.brun,
    surface: Colors.white,
    onSurface: Lf.encre,
    onSurfaceVariant: const Color(0xFF6B6455),
    surfaceContainerHighest: Lf.sable,
    outlineVariant: Lf.bord,
    error: Lf.rouge,
  );
  final texte = GoogleFonts.sourceSans3TextTheme(base.textTheme).apply(
    bodyColor: Lf.encre,
    displayColor: Lf.encre,
  );
  TextStyle? serif(TextStyle? s) => s?.copyWith(fontFamily: GoogleFonts.lora().fontFamily, fontWeight: FontWeight.w500);
  return base.copyWith(
    colorScheme: schema,
    scaffoldBackgroundColor: Lf.creme,
    textTheme: texte.copyWith(
      headlineLarge: serif(texte.headlineLarge),
      headlineMedium: serif(texte.headlineMedium),
      headlineSmall: serif(texte.headlineSmall),
      titleLarge: serif(texte.titleLarge),
      titleMedium: serif(texte.titleMedium)?.copyWith(fontSize: 18),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Lf.creme,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Lf.encre,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: Lf.serif(size: 21),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Lf.bord, width: 0.8),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Lf.vert,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Lf.vert,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Lf.vert,
        side: const BorderSide(color: Lf.bord),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Lf.bord),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Lf.bord),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Lf.vertClair,
      side: const BorderSide(color: Lf.bord),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Lf.vertClair,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.sourceSans3(
            fontSize: 12,
            color: s.contains(WidgetState.selected) ? Lf.vert : Lf.taupe,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? Lf.vert : Lf.taupe,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Lf.creme,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Lf.creme,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Lf.vert,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Lf.bord),
  );
}

/// Feuille du logo dessinée (pour le bandeau).
class FeuilleLogo extends StatelessWidget {
  const FeuilleLogo({super.key, this.taille = 24, this.couleur = const Color(0xFF8CC79C), this.nervure = Lf.vert});
  final double taille;
  final Color couleur;
  final Color nervure;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(taille * 0.7, taille),
        painter: _Feuille(couleur, nervure),
      );
}

class _Feuille extends CustomPainter {
  _Feuille(this.c, this.n);
  final Color c;
  final Color n;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height * 0.82;
    final p = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.05, h * 0.3, 0, h * 0.6, w * 0.15, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.95, w / 2, h)
      ..quadraticBezierTo(w * 0.7, h * 0.95, w * 0.85, h * 0.8)
      ..cubicTo(w, h * 0.6, w * 0.95, h * 0.3, w / 2, 0);
    canvas.drawPath(p, Paint()..color = c);
    canvas.drawLine(Offset(w / 2, h * 0.18), Offset(w / 2, h * 0.88),
        Paint()..color = n..strokeWidth = 1.3);
    final r = Paint()
      ..color = Lf.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(w / 2, h)
          ..quadraticBezierTo(w * 0.3, s.height * 0.92, w * 0.1, s.height * 0.95),
        r);
    canvas.drawPath(
        Path()
          ..moveTo(w / 2, h)
          ..quadraticBezierTo(w * 0.65, s.height * 0.92, w * 0.7, s.height),
        r);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Sillons, pousses et soleil du bandeau d'accueil.
class PaysageJardin extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawCircle(Offset(w - 46, 42), 17, Paint()..color = Lf.orange.withValues(alpha: 0.92));
    void colline(double y1, double y2, double y3, Color c) {
      canvas.drawPath(
          Path()
            ..moveTo(0, h - y1)
            ..quadraticBezierTo(w / 2, h - y2, w, h - y3)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          Paint()..color = c);
    }

    colline(58, 110, 66, const Color(0xFF3A7A4B));
    colline(36, 82, 40, const Color(0xFF46895A));
    colline(14, 52, 18, const Color(0xFF529766));
    final pousse = Paint()
      ..color = const Color(0xFF7DB78D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final x in [0.12, 0.5, 0.86]) {
      final bx = w * x;
      final by = h - (x == 0.5 ? 86 : 64);
      canvas.drawLine(Offset(bx, by), Offset(bx, by - 14), pousse);
      canvas.drawPath(
          Path()
            ..moveTo(bx, by - 6)
            ..quadraticBezierTo(bx - 8, by - 14, bx - 11, by - 9),
          pousse);
      canvas.drawPath(
          Path()
            ..moveTo(bx, by - 9)
            ..quadraticBezierTo(bx + 8, by - 17, bx + 11, by - 12),
          pousse);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Jauge circulaire de l'état du jardin.
class Jauge extends CustomPainter {
  Jauge(this.part);
  final double part;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 5;
    final fond = Paint()
      ..color = const Color(0xFFEFEAE0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(c, r, fond);
    if (part > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -1.5708,
        6.2832 * part.clamp(0, 1),
        false,
        Paint()
          ..color = Lf.feuille
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Jauge old) => old.part != part;
}
