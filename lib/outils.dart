import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

final db = FirebaseFirestore.instance;

/// Vrai quand le responsable est connecté sur ce téléphone.
final estAdmin = ValueNotifier<bool>(false);

/// Numéro de version de l'application installée (rempli au démarrage).
int versionLocale = 0;
String versionNom = '';

const etapes = [
  'Semis',
  'Levée',
  'Croissance',
  'Floraison',
  'Fructification',
  'Récolte',
];

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

String libelleFrequence(int h) => switch (h) {
      12 => 'Matin et soir',
      48 => 'Tous les deux jours',
      _ => 'Une fois par jour',
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

String _deux(int n) => n.toString().padLeft(2, '0');

String dateLisible(Timestamp ts) {
  final d = ts.toDate();
  const jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  return '${jours[d.weekday - 1]} ${_deux(d.day)}/${_deux(d.month)} à ${d.hour} h ${_deux(d.minute)}';
}

String dateCourte(Timestamp ts) {
  final d = ts.toDate();
  return '${_deux(d.day)}/${_deux(d.month)}/${d.year}';
}

Timestamp? tsDe(dynamic v) => v is Timestamp ? v : null;

// Les écritures ne sont pas attendues : hors ligne, elles restent en file
// d'attente sur le téléphone et partent dès que le réseau revient.
void ecrire(Future<dynamic> f) {
  f.then<void>((_) {}, onError: (Object e) {});
}

void message(BuildContext context, String texte) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texte)));
}

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
  ecrire(batch.commit());
  message(context, 'Arrosage de $parcelleNom enregistré');
}

Future<String?> demanderTexte(BuildContext context, String titre,
    String etiquette,
    {String initial = '', String bouton = 'Ajouter'}) {
  final ctrl = TextEditingController(text: initial);
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
          child: Text(bouton),
        ),
      ],
    ),
  );
}

Future<bool> confirmer(BuildContext context, String question,
    {String bouton = 'Supprimer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(bouton)),
      ],
    ),
  );
  return r == true;
}

/// Formulaire d'ajout ou de modification d'une parcelle (responsable).
Future<void> formulaireParcelle(BuildContext context,
    {String? id, Map<String, dynamic>? actuelle}) async {
  final nomCtrl = TextEditingController(text: actuelle?['nom'] as String? ?? '');
  final cultureCtrl =
      TextEditingController(text: actuelle?['culture'] as String? ?? '');
  int freq = (actuelle?['frequenceHeures'] as num?)?.toInt() ?? 24;
  if (![12, 24, 48].contains(freq)) freq = 24;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(id == null ? 'Nouvelle parcelle' : 'Modifier la parcelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              autofocus: id == null,
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
            child: Text(id == null ? 'Ajouter' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final donnees = {
    'nom': nomCtrl.text.trim(),
    'culture': cultureCtrl.text.trim(),
    'frequenceHeures': freq,
  };
  if (id == null) {
    ecrire(db.collection('parcelles').add({
      ...donnees,
      'dernierArrosage': null,
      'dernierPar': null,
    }));
  } else {
    ecrire(db.collection('parcelles').doc(id).update(donnees));
  }
}
