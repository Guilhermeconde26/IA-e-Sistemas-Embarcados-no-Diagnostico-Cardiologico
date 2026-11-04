// Tema do DECI: creme com destaques rosa-coral e traços marrom-escuro, a paleta do ícone do app.
import 'package:flutter/material.dart';

import 'deci_marca.dart';

class Cores {
  static const fundo = DeciCores.creme;
  static const painel = Colors.white;
  static const painel2 = Color(0xFFFFF7F4);
  static const linha = Color(0xFFF6DCD8);
  static const linhaForte = Color(0xFFEDC4C0);
  static const texto = DeciCores.marrom;
  static const suave = Color(0xFF8A6669);
  static const destaque = Color(0xFFF2456F); // botões e realces (coral um pouco mais fechado p/ contraste)
  static const destaqueEscuro = Color(0xFFC42452); // texto em destaque sobre fundo claro
  static const destaqueClaro = DeciCores.rosaPalido;
  static const aviso = Color(0xFFB7791F);
  static const avisoClaro = Color(0xFFFDF4E3);
  static const perigo = Color(0xFFB3261E);
  // papel de ECG rosado, traço marrom (bem distinto das cores das classes)
  static const ecgGrade = Color(0xFFFBE6E4);
  static const ecgGradeForte = Color(0xFFF4C7C6);
  static const ecgTraco = Color(0xFF4A1820);
}

// Cores das classes: semânticas (verde = normal, vermelho = ventricular) e diferentes do rosa da marca
const Map<String, Color> coresClasse = {
  'N': Color(0xFF2E9E6B),
  'S': Color(0xFFD08A12),
  'V': Color(0xFFB3261E),
  'F': Color(0xFF7E57C2),
};

const Map<String, String> descricaoClasse = {
  'N': 'Normal (inclui bloqueios de ramo)',
  'S': 'Ectópico supraventricular',
  'V': 'Ectópico ventricular (extrassístole)',
  'F': 'Fusão ventricular + normal',
};

Color corDaClasse(String? c) => coresClasse[c] ?? Cores.suave;

ThemeData temaDeci() {
  final esquema = ColorScheme.fromSeed(
    seedColor: DeciCores.coral,
    primary: Cores.destaque,
    onPrimary: Colors.white,
    surface: Cores.painel,
    onSurface: Cores.texto,
    brightness: Brightness.light,
  );
  final raio = BorderRadius.circular(14);
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Cores.fundo,
    iconTheme: const IconThemeData(color: Cores.texto),
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.fundo,
      foregroundColor: Cores.texto,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: Cores.texto, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Cores.painel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Cores.linha)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent, // o próprio ícone (blob) já indica a aba
      surfaceTintColor: Colors.transparent,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Cores.destaqueEscuro : Cores.suave)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.destaque,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Cores.linha,
        disabledForegroundColor: Cores.suave,
        iconColor: Colors.white,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: raio),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.texto,
        iconColor: Cores.texto,
        minimumSize: const Size(0, 46),
        side: const BorderSide(color: Cores.linhaForte),
        shape: RoundedRectangleBorder(borderRadius: raio),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Cores.destaqueEscuro)),
    sliderTheme: const SliderThemeData(activeTrackColor: Cores.destaque, thumbColor: Cores.destaque, inactiveTrackColor: Cores.linha),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Cores.suave),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Cores.destaque : Cores.linha),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Cores.destaque),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Cores.texto,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: raio, borderSide: const BorderSide(color: Cores.linhaForte)),
      enabledBorder: OutlineInputBorder(borderRadius: raio, borderSide: const BorderSide(color: Cores.linhaForte)),
      focusedBorder: OutlineInputBorder(borderRadius: raio, borderSide: const BorderSide(color: Cores.destaque, width: 2)),
    ),
    dividerColor: Cores.linha,
  );
}
