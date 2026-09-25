import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'outils.dart';

// ---------- Connexion du responsable ----------

class ConnexionResponsable extends StatefulWidget {
  const ConnexionResponsable({super.key});

  @override
  State<ConnexionResponsable> createState() => _ConnexionResponsableState();
}

class _ConnexionResponsableState extends State<ConnexionResponsable> {
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _occupe = false;

  Future<void> _connecter() async {
    setState(() => _occupe = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _mdp.text,
      );
      estAdmin.value = true;
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        message(context,
            'Connexion refusée. Vérifie l’e-mail, le mot de passe et le réseau.');
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace responsable')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'E-mail', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mdp,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Mot de passe', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _occupe ? null : _connecter,
            child: const Text('Se connecter'),
          ),
        ],
      ),
    );
  }
}

// ---------- Gestion des élèves ----------

class GestionEleves extends StatelessWidget {
  const GestionEleves({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Élèves du groupe')),
      body: StreamBuilder(
        stream: db.collection('eleves').orderBy('nom').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun élève. Ajoute-les en bas.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final d in docs)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(d.data()['nom'] as String? ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Renommer',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final n = await demanderTexte(
                              context, 'Renommer', 'Prénom et nom',
                              initial: d.data()['nom'] as String? ?? '',
                              bouton: 'Enregistrer');
                          if (n != null) ecrire(d.reference.update({'nom': n}));
                        },
                      ),
                      IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmer(context,
                              'Retirer ${d.data()['nom']} du groupe ? Ses arrosages restent dans le journal.',
                              bouton: 'Retirer')) {
                            ecrire(d.reference.delete());
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final n =
              await demanderTexte(context, 'Ajouter un élève', 'Prénom et nom');
          if (n != null) ecrire(db.collection('eleves').add({'nom': n}));
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Élève'),
      ),
    );
  }
}

// ---------- Journal de tous les arrosages ----------

class JournalArrosages extends StatefulWidget {
  const JournalArrosages({super.key});

  @override
  State<JournalArrosages> createState() => _JournalArrosagesState();
}

class _JournalArrosagesState extends State<JournalArrosages> {
  int _jours = 7; // 0 = tout
  String? _eleve;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal des arrosages')),
      body: StreamBuilder(
        stream: db
            .collection('arrosages')
            .orderBy('date', descending: true)
            .limit(1000)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final limite = DateTime.now().subtract(Duration(days: _jours));
          final tous = snap.data!.docs.where((d) {
            final ts = tsDe(d.data()['date']);
            return _jours == 0 || (ts != null && ts.toDate().isAfter(limite));
          }).toList();
          final noms = <String>{
            for (final d in tous) d.data()['eleve'] as String? ?? ''
          }.toList()
            ..sort();
          final compte = <String, int>{};
          for (final d in tous) {
            final n = d.data()['eleve'] as String? ?? '';
            compte[n] = (compte[n] ?? 0) + 1;
          }
          final classement = compte.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final liste = _eleve == null
              ? tous
              : tous.where((d) => d.data()['eleve'] == _eleve).toList();
          final theme = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final j in const [7, 30, 0])
                    ChoiceChip(
                      label: Text(j == 0 ? 'Tout' : '$j derniers jours'),
                      selected: _jours == j,
                      onSelected: (_) => setState(() => _jours = j),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Arrosages par élève', style: theme.titleMedium),
              if (classement.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucun arrosage sur cette période.'),
                ),
              for (final e in classement)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  trailing: Text('${e.value}', style: theme.titleMedium),
                  selected: _eleve == e.key,
                  onTap: () => setState(
                      () => _eleve = _eleve == e.key ? null : e.key),
                ),
              const SizedBox(height: 16),
              Text(
                _eleve == null ? 'Détail' : 'Détail · $_eleve',
                style: theme.titleMedium,
              ),
              if (_eleve != null && !noms.contains(_eleve))
                const Text('Aucun arrosage pour cet élève sur cette période.'),
              for (final d in liste)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.water_drop_outlined),
                  title: Text(
                      '${d.data()['eleve'] ?? ''} · ${d.data()['parcelle'] ?? ''}'),
                  subtitle: Text(tsDe(d.data()['date']) != null
                      ? dateLisible(tsDe(d.data()['date'])!)
                      : ''),
                  onLongPress: () async {
                    if (await confirmer(context, 'Supprimer cet arrosage ?')) {
                      ecrire(d.reference.delete());
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Publication d'une mise à jour ----------

class PublierMiseAJour extends StatefulWidget {
  const PublierMiseAJour({super.key});

  @override
  State<PublierMiseAJour> createState() => _PublierMiseAJourState();
}

class _PublierMiseAJourState extends State<PublierMiseAJour> {
  final _version = TextEditingController();
  final _lien = TextEditingController();
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    db.collection('config').doc('app').get().then((s) {
      final d = s.data();
      if (!mounted) return;
      setState(() {
        _version.text = '${d?['version'] ?? ''}';
        _lien.text = d?['lien'] as String? ?? '';
        _charge = true;
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _charge = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mise à jour')),
      body: !_charge
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Version installée sur ce téléphone : $versionNom (n° $versionLocale)'),
                const SizedBox(height: 16),
                const Text(
                    'Pour proposer une nouvelle version aux élèves, indique son numéro et le lien de téléchargement de l’APK. Le bandeau « Mise à jour disponible » apparaîtra sur les téléphones qui ont une version plus ancienne.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _version,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Numéro de la nouvelle version',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lien,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Lien de téléchargement',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final v = int.tryParse(_version.text.trim());
                    final l = _lien.text.trim();
                    if (v == null || !l.startsWith('http')) {
                      message(context, 'Numéro ou lien invalide.');
                      return;
                    }
                    ecrire(db.collection('config').doc('app').set(
                        {'version': v, 'lien': l, 'date': Timestamp.now()},
                        SetOptions(merge: true)));
                    message(context, 'Mise à jour publiée');
                    Navigator.pop(context);
                  },
                  child: const Text('Publier'),
                ),
              ],
            ),
    );
  }
}
