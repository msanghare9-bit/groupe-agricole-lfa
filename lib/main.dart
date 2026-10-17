import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accueil.dart';
import 'admin.dart';
import 'firebase_options.dart';
import 'notifs.dart';
import 'outils.dart';
import 'planning.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  try {
    final info = await PackageInfo.fromPlatform();
    versionLocale = int.tryParse(info.buildNumber) ?? 0;
    versionNom = info.version;
  } catch (_) {}
  await initNotifications();
  runApp(const GroupeAgricoleApp());
}

class GroupeAgricoleApp extends StatelessWidget {
  const GroupeAgricoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Groupe Agricole',
      debugShowCheckedModeBanner: false,
      theme: themeLfarm(),
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
      abonner(estAdmin.value ? null : _nom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) demanderAutorisations(context);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur =
          'Connexion impossible. Vérifie internet puis réessaie.\n\n(Détail : $e)');
    }
  }

  Future<void> _choisirNom(String? nom) async {
    final prefs = await SharedPreferences.getInstance();
    if (nom == null) {
      await prefs.remove('nom');
    } else {
      await prefs.setString('nom', nom);
    }
    abonner(nom);
    if (nom == null) annulerRappels();
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
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ConnexionResponsable())),
            icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
            label: const Text('Responsable'),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: db.collection('eleves').orderBy('nom').snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  const SizedBox(height: 8),
                  const Center(child: FeuilleLogo(taille: 64, couleur: Lf.feuille, nervure: Color(0xFFA9CDB1))),
                  const SizedBox(height: 14),
                  Center(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'LFA', style: Lf.serif(size: 34, color: Lf.vert, weight: FontWeight.w600)),
                        TextSpan(text: 'RM', style: Lf.serif(size: 34, color: Lf.orange, weight: FontWeight.w600)),
                      ]),
                      style: const TextStyle(letterSpacing: 5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(Lf.devise,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Lf.taupe, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 32),
                  Text('Qui es-tu ?', style: Lf.serif(size: 22)),
                  const SizedBox(height: 4),
                  const Text('Choisis ton nom dans la liste.', style: TextStyle(color: Lf.taupe)),
                  const SizedBox(height: 12),
                  if (snap.hasError)
                    Text('Erreur : ${snap.error}')
                  else if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (docs.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          "Aucun élève pour l'instant. Le responsable doit d'abord ajouter les membres du groupe.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < docs.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 64),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: i.isEven ? Lf.vertClair : Lf.orangeClair,
                                child: Text(
                                  initiales(docs[i].data()['nom'] as String? ?? ''),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: i.isEven ? Lf.vert : Lf.orangeFonce),
                                ),
                              ),
                              title: Text(docs[i].data()['nom'] as String? ?? ''),
                              trailing: const Icon(Icons.chevron_right, color: Lf.taupe),
                              onTap: () => onChoisi(docs[i].data()['nom'] as String? ?? ''),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
