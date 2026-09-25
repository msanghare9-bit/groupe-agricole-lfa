import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'outils.dart';

Timestamp _ou0(dynamic v) => tsDe(v) ?? Timestamp(0, 0);

class FicheParcelle extends StatelessWidget {
  const FicheParcelle({super.key, required this.id, required this.eleve});
  final String id;
  final String eleve;

  Future<void> _changerEtape(BuildContext context, String? actuelle) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Nouvelle étape')),
            for (final e in etapes)
              ListTile(
                leading: Icon(e == actuelle
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(e),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
    if (choix == null || choix == actuelle) return;
    ecrire(db.collection('parcelles').doc(id).update({
      'etape': choix,
      'etapes': FieldValue.arrayUnion([
        {'nom': choix, 'date': Timestamp.now(), 'par': eleve}
      ]),
    }));
    if (context.mounted) message(context, 'Étape « $choix » enregistrée');
  }

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    return StreamBuilder(
      stream: db.collection('parcelles').doc(id).snapshots(),
      builder: (context, snap) {
        final p = snap.data?.data();
        if (snap.hasData && p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Cette parcelle a été supprimée.')),
          );
        }
        if (p == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final nom = p['nom'] as String? ?? '';
        final culture = p['culture'] as String? ?? '';
        final etape = p['etape'] as String?;
        final historique =
            (p['etapes'] as List? ?? []).whereType<Map>().toList();
        final freq = (p['frequenceHeures'] as num?)?.toInt() ?? 24;
        final theme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(nom),
            actions: admin
                ? [
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          formulaireParcelle(context, id: id, actuelle: p),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmer(context,
                            'Supprimer $nom ? Ses arrosages resteront dans le journal.')) {
                          ecrire(db.collection('parcelles').doc(id).delete());
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                  ]
                : null,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (culture.isNotEmpty) Text(culture, style: theme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                  'Arrosage ${libelleFrequence(freq).toLowerCase()} · dernier ${depuis(tsDe(p['dernierArrosage']))}'),
              const SizedBox(height: 20),
              Text('Étape', style: theme.titleMedium),
              Row(
                children: [
                  Chip(label: Text(etape ?? 'Non renseignée')),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _changerEtape(context, etape),
                    icon: const Icon(Icons.trending_up),
                    label: const Text('Changer'),
                  ),
                ],
              ),
              for (final h in historique.reversed)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    [
                      '${h['nom'] ?? ''}',
                      if (tsDe(h['date']) != null) dateCourte(tsDe(h['date'])!),
                      if (h['par'] != null) '${h['par']}',
                    ].join(' · '),
                    style: theme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              Text('Derniers arrosages', style: theme.titleMedium),
              _Arrosages(id: id, admin: admin),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                      child: Text('Journal de bord', style: theme.titleMedium)),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NouvelleObservation(
                            parcelleId: id, parcelleNom: nom, eleve: eleve),
                      ),
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              _Journal(id: id, admin: admin),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => enregistrerArrosage(context, id, nom, eleve),
            icon: const Icon(Icons.water_drop_outlined),
            label: const Text("J'ai arrosé"),
          ),
        );
      },
    );
  }
}

class _Arrosages extends StatelessWidget {
  const _Arrosages({required this.id, required this.admin});
  final String id;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db
          .collection('arrosages')
          .where('parcelleId', isEqualTo: id)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs.toList()
          ..sort((a, b) =>
              _ou0(b.data()['date']).compareTo(_ou0(a.data()['date'])));
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun arrosage enregistré.'),
          );
        }
        return Column(
          children: [
            for (final d in docs.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.water_drop_outlined),
                title: Text(d.data()['eleve'] as String? ?? ''),
                subtitle: Text(tsDe(d.data()['date']) != null
                    ? dateLisible(tsDe(d.data()['date'])!)
                    : ''),
                onLongPress: admin
                    ? () async {
                        if (await confirmer(context, 'Supprimer cet arrosage ?')) {
                          ecrire(d.reference.delete());
                        }
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _Journal extends StatelessWidget {
  const _Journal({required this.id, required this.admin});
  final String id;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream:
          db.collection('journal').where('parcelleId', isEqualTo: id).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs.toList()
          ..sort((a, b) =>
              _ou0(b.data()['date']).compareTo(_ou0(a.data()['date'])));
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucune observation pour le moment.'),
          );
        }
        return Column(
          children: [
            for (final d in docs) CarteObservation(doc: d, admin: admin),
          ],
        );
      },
    );
  }
}

class CarteObservation extends StatelessWidget {
  const CarteObservation(
      {super.key,
      required this.doc,
      required this.admin,
      this.afficherParcelle = false});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool admin;
  final bool afficherParcelle;

  @override
  Widget build(BuildContext context) {
    final o = doc.data();
    final image = o['image'] as String?;
    final texte = o['texte'] as String? ?? '';
    final ts = tsDe(o['date']);
    Uint8List? octets;
    if (image != null) {
      try {
        octets = base64Decode(image);
      } catch (_) {}
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: admin
            ? () async {
                if (await confirmer(context, 'Supprimer cette observation ?')) {
                  ecrire(doc.reference.delete());
                }
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (octets != null)
              Image.memory(octets,
                  width: double.infinity, fit: BoxFit.cover, gaplessPlayback: true),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (afficherParcelle)
                    Text('${o['parcelle'] ?? ''}',
                        style: Theme.of(context).textTheme.labelLarge),
                  if (texte.isNotEmpty) Text(texte),
                  const SizedBox(height: 4),
                  Text(
                    '${o['eleve'] ?? ''}${ts != null ? ' · ${dateLisible(ts)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NouvelleObservation extends StatefulWidget {
  const NouvelleObservation({
    super.key,
    required this.parcelleId,
    required this.parcelleNom,
    required this.eleve,
  });
  final String parcelleId;
  final String parcelleNom;
  final String eleve;

  @override
  State<NouvelleObservation> createState() => _NouvelleObservationState();
}

class _NouvelleObservationState extends State<NouvelleObservation> {
  final _texte = TextEditingController();
  Uint8List? _image;
  bool _occupe = false;

  Future<void> _prendre(ImageSource source) async {
    setState(() => _occupe = true);
    try {
      final f = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 60,
      );
      if (f != null) {
        final b = await f.readAsBytes();
        if (!mounted) return;
        if (b.length > 700000) {
          message(context, 'Photo trop lourde, réessaie.');
        } else {
          setState(() => _image = b);
        }
      }
    } catch (_) {
      if (mounted) message(context, "Impossible d'ouvrir l'appareil photo.");
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  void _publier() {
    final t = _texte.text.trim();
    final img = _image;
    if (t.isEmpty && img == null) {
      message(context, 'Ajoute une photo ou un texte.');
      return;
    }
    ecrire(db.collection('journal').add({
      'parcelleId': widget.parcelleId,
      'parcelle': widget.parcelleNom,
      'eleve': widget.eleve,
      'date': Timestamp.now(),
      'texte': t,
      if (img != null) 'image': base64Encode(img),
    }));
    message(context, 'Observation enregistrée');
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      appBar: AppBar(title: Text('Observation · ${widget.parcelleNom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (img != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(img),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _occupe ? null : () => _prendre(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _occupe ? null : () => _prendre(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _texte,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Ce que tu observes',
              hintText: 'Ex. premières fleurs, feuilles jaunes, pucerons…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _occupe ? null : _publier,
            icon: const Icon(Icons.send),
            label: const Text('Publier'),
          ),
        ],
      ),
    );
  }
}

/// Choix de l'endroit concerné, puis ouverture du formulaire de remarque.
Future<void> nouvelleRemarque(BuildContext context, String eleve) async {
  final parcelles = await db.collection('parcelles').orderBy('nom').get();
  if (!context.mounted) return;
  final choix = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Ta remarque concerne…')),
          ListTile(
            leading: const Icon(Icons.yard_outlined),
            title: const Text('Le jardin en général'),
            subtitle: const Text('Tuyau, clôture, réservoir, outils…'),
            onTap: () => Navigator.pop(ctx, ['jardin', 'Jardin (général)']),
          ),
          for (final d in parcelles.docs)
            ListTile(
              leading: const Icon(Icons.grass_outlined),
              title: Text([
                '${d.data()['nom'] ?? ''}',
                if ('${d.data()['culture'] ?? ''}'.isNotEmpty)
                  '${d.data()['culture']}',
              ].join(' · ')),
              onTap: () =>
                  Navigator.pop(ctx, [d.id, '${d.data()['nom'] ?? ''}']),
            ),
        ],
      ),
    ),
  );
  if (choix == null || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NouvelleObservation(
          parcelleId: choix[0], parcelleNom: choix[1], eleve: eleve),
    ),
  );
}

/// Toutes les remarques récentes, tous endroits confondus (responsable).
class ToutesRemarques extends StatelessWidget {
  const ToutesRemarques({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remarques et photos')),
      body: StreamBuilder(
        stream: db
            .collection('journal')
            .orderBy('date', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucune remarque pour le moment.'));
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final d in docs)
                CarteObservation(doc: d, admin: true, afficherParcelle: true),
            ],
          );
        },
      ),
    );
  }
}
