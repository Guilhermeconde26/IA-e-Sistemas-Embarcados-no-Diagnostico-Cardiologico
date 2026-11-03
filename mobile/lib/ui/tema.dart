// Tema do IC ECG: branco com detalhes verde claro (mesma paleta do painel web).
import 'package:flutter/material.dart';

class Cores {
  static const fundo = Color(0xFFF5FAF7);
  static const painel = Colors.white;
  static const painel2 = Color(0xFFF3F8F5);
  static const linha = Color(0xFFE1ECE5);
  static const linhaForte = Color(0xFFC9DDD0);
  static const texto = Color(0xFF15261C);
  static const suave = Color(0xFF64776B);
  static const verde = Color(0xFF4CC982);
  static const verdeEscuro = Color(0xFF0F6B3A);
  static const verdeClaro = Color(0xFFE9F8EF);
  static const aviso = Color(0xFFB7791F);
  static const avisoClaro = Color(0xFFFDF4E3);
  static const perigo = Color(0xFFD64545);
  static const ecgGrade = Color(0xFFEDF7F0);
  static const ecgGradeForte = Color(0xFFCFE8D7);
  static const ecgTraco = Color(0xFF128048);
}

const Map<String, Color> coresClasse = {
  'N': Color(0xFF1F9D55),
  'S': Color(0xFFC27C0E),
  'V': Color(0xFFD64545),
  'F': Color(0xFF8B5CF6),
};

const Map<String, String> descricaoClasse = {
  'N': 'Normal (inclui bloqueios de ramo)',
  'S': 'Ectópico supraventricular',
  'V': 'Ectópico ventricular (extrassístole)',
  'F': 'Fusão ventricular + normal',
};

Color corDaClasse(String? c) => coresClasse[c] ?? Cores.suave;

ThemeData temaIcEcg() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.verde,
    primary: Cores.verde,
    onPrimary: Colors.white,
    surface: Cores.painel,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Cores.fundo,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Cores.texto,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Cores.painel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Cores.linha)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Cores.verdeClaro,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Cores.verdeEscuro : Cores.suave)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Cores.verdeEscuro : Cores.suave)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.verde,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.texto,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: Cores.linhaForte),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Cores.linhaForte)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Cores.linhaForte)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Cores.verde, width: 2)),
    ),
    dividerColor: Cores.linha,
  );
}
