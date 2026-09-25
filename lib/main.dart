import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accueil.dart';
import 'admin.dart';
import 'firebase_options.dart';
import 'outils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  try {
    final info = await PackageInfo.fromPlatform();
    versionLocale = int.tryParse(info.buildNumber) ?? 0;
    versionNom = info.version;
  } catch (_) {}
  runApp(const GroupeAgricoleApp());
}

class GroupeAgricoleApp extends StatelessWidget {
  const GroupeAgricoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Groupe Agricole',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
      ),
      home: const Demarrage(),
    );
  }
}

class Demarrage extends StatefulWidget {
  const Demarrage({super.key});

  @override
  State<Demarrage> createState() => _DemarrageState();
}

class _DemarrageState extends State<Demarrage> {
  String? _nom;
  bool _pret = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _erreur = null);
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      estAdmin.value = !(FirebaseAuth.instance.currentUser?.isAnonymous ?? true);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _nom = prefs.getString('nom');
        _pret = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _erreur =
          'La première connexion demande internet. Active les données puis réessaie.');
    }
  }

  Future<void> _choisirNom(String? nom) async {
    final prefs = await SharedPreferences.getInstance();
    if (nom == null) {
      await prefs.remove('nom');
    } else {
      await prefs.setString('nom', nom);
    }
    if (!mounted) return;
    setState(() => _nom = nom);
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_erreur!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _init, child: const Text('Réessayer')),
              ],
            ),
          ),
        ),
      );
    }
    if (!_pret) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ValueListenableBuilder<bool>(
      valueListenable: estAdmin,
      builder: (context, admin, _) {
        if (admin) {
          return Accueil(nom: 'Responsable', onChangerNom: () {});
        }
        if (_nom == null) return ChoixNom(onChoisi: _choisirNom);
        return Accueil(nom: _nom!, onChangerNom: () => _choisirNom(null));
      },
    );
  }
}

class ChoixNom extends StatelessWidget {
  const ChoixNom({super.key, required this.onChoisi});
  final ValueChanged<String> onChoisi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qui es-tu ?'),
        actions: [
          IconButton(
            tooltip: 'Espace responsable',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ConnexionResponsable())),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: db.collection('eleves').orderBy('nom').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Aucun élève pour l'instant. Le responsable doit d'abord ajouter les membres du groupe.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final d in docs)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(d.data()['nom'] as String? ?? ''),
                  onTap: () => onChoisi(d.data()['nom'] as String? ?? ''),
                ),
            ],
          );
        },
      ),
    );
  }
}
