import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const GroupeAgricoleApp());
}

final db = FirebaseFirestore.instance;

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

// ---------- Outils ----------

enum Etat { arrosee, aArroser, enRetard }

Etat etatDe(Map<String, dynamic> p) {
  final ts = p['dernierArrosage'];
  if (ts is! Timestamp) return Etat.enRetard;
  final heures = DateTime.now().difference(ts.toDate()).inMinutes / 60;
  final freq = (p['frequenceHeures'] as num?)?.toDouble() ?? 24;
  if (heures < freq) return Etat.arrosee;
  if (heures < freq * 2) return Etat.aArroser;
  return Etat.enRetard;
}

Color couleur(Etat e) => switch (e) {
      Etat.arrosee => const Color(0xFF2E7D32),
      Etat.aArroser => const Color(0xFFEF8F00),
      Etat.enRetard => const Color(0xFFC62828),
    };

String libelle(Etat e) => switch (e) {
      Etat.arrosee => 'Arrosée',
      Etat.aArroser => 'À arroser',
      Etat.enRetard => 'En retard',
    };

String depuis(Timestamp? ts) {
  if (ts == null) return 'jamais arrosée';
  final d = DateTime.now().difference(ts.toDate());
  if (d.inMinutes < 5) return "à l'instant";
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  final j = d.inDays;
  return j == 1 ? 'hier' : 'il y a $j jours';
}

String dateLisible(Timestamp ts) {
  final d = ts.toDate();
  const jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${jours[d.weekday - 1]} ${deux(d.day)}/${deux(d.month)} à ${d.hour} h ${deux(d.minute)}';
}

// Les écritures ne sont pas attendues : hors ligne, elles restent en file
// d'attente sur le téléphone et partent dès que le réseau revient.
void enregistrerArrosage(
    BuildContext context, String parcelleId, String parcelleNom, String eleve) {
  final maintenant = Timestamp.now();
  final batch = db.batch();
  batch.set(db.collection('arrosages').doc(), {
    'parcelleId': parcelleId,
    'parcelle': parcelleNom,
    'eleve': eleve,
    'date': maintenant,
  });
  batch.update(db.collection('parcelles').doc(parcelleId), {
    'dernierArrosage': maintenant,
    'dernierPar': eleve,
  });
  batch.commit().catchError((_) {});
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Arrosage de $parcelleNom enregistré')),
  );
}

Future<String?> demanderTexte(
    BuildContext context, String titre, String etiquette) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: etiquette),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
          child: const Text('Ajouter'),
        ),
      ],
    ),
  );
}

Future<void> ajouterParcelle(BuildContext context) async {
  final nomCtrl = TextEditingController();
  final cultureCtrl = TextEditingController();
  int freq = 24;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Nouvelle parcelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Nom (ex. Planche 1)'),
            ),
            TextField(
              controller: cultureCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Culture (ex. Tomates)'),
            ),
            const SizedBox(height: 16),
            DropdownButton<int>(
              value: freq,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 12, child: Text('Matin et soir')),
                DropdownMenuItem(value: 24, child: Text('Une fois par jour')),
                DropdownMenuItem(value: 48, child: Text('Tous les deux jours')),
              ],
              onChanged: (v) => setD(() => freq = v ?? 24),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (nomCtrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    db.collection('parcelles').add({
      'nom': nomCtrl.text.trim(),
      'culture': cultureCtrl.text.trim(),
      'frequenceHeures': freq,
      'dernierArrosage': null,
      'dernierPar': null,
    });
  }
}

// ---------- Démarrage ----------

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
    if (_nom == null) return ChoixNom(onChoisi: _choisirNom);
    return Accueil(nom: _nom!, onChangerNom: () => _choisirNom(null));
  }
}

// ---------- Choix du nom ----------

class ChoixNom extends StatelessWidget {
  const ChoixNom({super.key, required this.onChoisi});
  final ValueChanged<String> onChoisi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Qui es-tu ?')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  "Aucun élève pour l'instant. Ajoute le premier avec le bouton en bas.",
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final nom =
              await demanderTexte(context, 'Ajouter un élève', 'Prénom et nom');
          if (nom != null) db.collection('eleves').add({'nom': nom});
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter un élève'),
      ),
    );
  }
}

// ---------- Accueil ----------

class Accueil extends StatelessWidget {
  const Accueil({super.key, required this.nom, required this.onChangerNom});
  final String nom;
  final VoidCallback onChangerNom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jardin du LFA'),
        actions: [
          IconButton(
            tooltip: "Changer d'élève",
            icon: const Icon(Icons.switch_account_outlined),
            onPressed: onChangerNom,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('parcelles')
            .orderBy('nom')
            .snapshots(includeMetadataChanges: true),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          final enAttente = snap.data!.metadata.hasPendingWrites;
          final horsLigne = snap.data!.metadata.isFromCache;
          final nbOk =
              docs.where((d) => etatDe(d.data()) == Etat.arrosee).length;
          final nbRetard =
              docs.where((d) => etatDe(d.data()) == Etat.enRetard).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Bonjour $nom',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _Chiffre(
                          titre: 'Arrosées', valeur: '$nbOk/${docs.length}')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Chiffre(
                      titre: 'En retard',
                      valeur: '$nbRetard',
                      couleur: couleur(Etat.enRetard),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    enAttente
                        ? Icons.cloud_upload_outlined
                        : (horsLigne
                            ? Icons.cloud_off_outlined
                            : Icons.cloud_done_outlined),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(enAttente
                      ? "Arrosages en attente d'envoi"
                      : (horsLigne ? 'Hors ligne' : 'Tout est envoyé')),
                ],
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucune parcelle. Ajoute la première avec le bouton en bas.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final d in docs) _CarteParcelle(doc: d, eleve: nom),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ajouterParcelle(context),
        icon: const Icon(Icons.add),
        label: const Text('Parcelle'),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.titre, required this.valeur, this.couleur});
  final String titre;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: Theme.of(context).textTheme.bodySmall),
            Text(
              valeur,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: couleur),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteParcelle extends StatelessWidget {
  const _CarteParcelle({required this.doc, required this.eleve});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String eleve;

  @override
  Widget build(BuildContext context) {
    final p = doc.data();
    final etat = etatDe(p);
    final nomP = p['nom'] as String? ?? '';
    final culture = p['culture'] as String? ?? '';
    return Card(
      child: ListTile(
        leading: CircleAvatar(radius: 8, backgroundColor: couleur(etat)),
        title: Text(culture.isEmpty ? nomP : '$nomP · $culture'),
        subtitle: Text(
            '${libelle(etat)} · ${depuis(p['dernierArrosage'] as Timestamp?)}'),
        trailing: etat == Etat.arrosee
            ? null
            : IconButton.filledTonal(
                tooltip: "J'ai arrosé",
                icon: const Icon(Icons.water_drop_outlined),
                onPressed: () =>
                    enregistrerArrosage(context, doc.id, nomP, eleve),
              ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FicheParcelle(id: doc.id, nom: nomP, eleve: eleve),
          ),
        ),
      ),
    );
  }
}

// ---------- Fiche d'une parcelle ----------

class FicheParcelle extends StatelessWidget {
  const FicheParcelle(
      {super.key, required this.id, required this.nom, required this.eleve});
  final String id;
  final String nom;
  final String eleve;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(nom)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('arrosages')
            .where('parcelleId', isEqualTo: id)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final liste = snap.data!.docs.map((d) => d.data()).toList()
            ..sort((a, b) =>
                (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));
          if (liste.isEmpty) {
            return const Center(child: Text('Aucun arrosage enregistré.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Derniers arrosages',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final a in liste.take(30))
                ListTile(
                  leading: const Icon(Icons.water_drop_outlined),
                  title: Text(a['eleve'] as String? ?? ''),
                  subtitle: Text(dateLisible(a['date'] as Timestamp)),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => enregistrerArrosage(context, id, nom, eleve),
        icon: const Icon(Icons.water_drop_outlined),
        label: const Text("J'ai arrosé"),
      ),
    );
  }
}
