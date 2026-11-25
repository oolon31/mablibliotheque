import 'package:material_ui/material_ui.dart';

/// Thème et langue de l'application. Le root de l'application est placé au-dessus pour que
/// les écrans ouverts par-dessus l'accueil aient accès à la bibliothèque.
class BibliothequeApp extends StatelessWidget {
  const BibliothequeApp({super.key, required this.home, this.navigatorKey});

  final Widget home;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8C4A2F), brightness: b),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Ma Bibliothèque',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    );
  }
}
