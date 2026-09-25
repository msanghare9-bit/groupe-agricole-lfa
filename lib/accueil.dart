import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin.dart';
import 'fiche.dart';
import 'outils.dart';
import 'planning.dart';

class Accueil extends StatelessWidget {
  const Accueil({super.key, required this.nom, required this.onChangerNom});
  final String nom;
  final VoidCallback onChangerNom;

  Future<void> _deconnecter(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      estAdmin.value = false;
    } catch (_) {
      if (context.mounted) {
        message(context, 'La déconnexion demande internet. Réessaie avec du réseau.');
      }
    }
  }

  void _menu(BuildContext context, String choix) {
    Widget? page;
    switch (choix) {
      case 'nom':
        onChangerNom();
        return;
      case 'connexion':
        page = const ConnexionResponsable();
      case 'eleves':
        page = const GestionEleves();
      case 'journal':
        page = const JournalArrosages();
      case 'maj':
        page = const PublierMiseAJour();
      case 'planning':
        page = PagePlanning(nom: nom);
      case 'binomes':
        page = const GestionBinomes();
      case 'demandes':
        page = const DemandesRemplacement();
      case 'annonce':
        page = const EnvoyerAnnonce();
      case 'reglages':
        page = const ReglagesPlanning();
      case 'deconnexion':
        _deconnecter(context);
        return;
    }
    final cible = page;
    if (cible != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => cible));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jardin du LFA'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (c) => _menu(context, c),
            itemBuilder: (_) => admin
                ? const [
                    PopupMenuItem(
                        value: 'planning', child: Text('Emploi du temps')),
                    PopupMenuItem(value: 'binomes', child: Text('Binômes')),
                    PopupMenuItem(
                        value: 'demandes',
                        child: Text('Demandes de remplacement')),
                    PopupMenuItem(
                        value: 'annonce', child: Text('Annonce au groupe')),
                    PopupMenuItem(
                        value: 'reglages',
                        child: Text('Réglages du planning')),
                    PopupMenuItem(value: 'eleves', child: Text('Élèves')),
                    PopupMenuItem(
                        value: 'journal', child: Text('Journal des arrosages')),
                    PopupMenuItem(
                        value: 'maj', child: Text("Mise à jour de l'application")),
                    PopupMenuItem(
                        value: 'deconnexion', child: Text('Se déconnecter')),
                  ]
                : const [
                    PopupMenuItem(
                        value: 'planning', child: Text('Emploi du temps')),
                    PopupMenuItem(value: 'nom', child: Text("Changer d'élève")),
                    PopupMenuItem(
                        value: 'connexion', child: Text('Espace responsable')),
                  ],
          ),
        ],
      ),
      body: StreamBuilder(
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const BandeauMiseAJour(),
              const BandeauAnnonce(),
              if (!admin) ProchainTour(nom: nom),
              const SizedBox(height: 8),
              Text(admin ? 'Espace responsable' : 'Bonjour $nom',
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
                      ? "Données en attente d'envoi"
                      : (horsLigne ? 'Hors ligne' : 'Tout est envoyé')),
                ],
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    admin
                        ? 'Aucune parcelle. Ajoute la première avec le bouton en bas.'
                        : "Aucune parcelle pour l'instant.",
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final d in docs) _CarteParcelle(doc: d, eleve: nom),
            ],
          );
        },
      ),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: () => formulaireParcelle(context),
              icon: const Icon(Icons.add),
              label: const Text('Parcelle'),
            )
          : null,
    );
  }
}

class BandeauMiseAJour extends StatelessWidget {
  const BandeauMiseAJour({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('config').doc('app').snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null) return const SizedBox.shrink();
        final version = (d['version'] as num?)?.toInt() ?? 0;
        final lien = d['lien'] as String? ?? '';
        if (version <= versionLocale || lien.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Mise à jour disponible'),
            subtitle: const Text('Touche pour installer la nouvelle version.'),
            onTap: () => launchUrl(Uri.parse(lien),
                mode: LaunchMode.externalApplication),
          ),
        );
      },
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
    final etape = p['etape'] as String?;
    return Card(
      child: ListTile(
        leading: CircleAvatar(radius: 8, backgroundColor: couleur(etat)),
        title: Text(culture.isEmpty ? nomP : '$nomP · $culture'),
        subtitle: Text([
          '${libelle(etat)} · ${depuis(tsDe(p['dernierArrosage']))}',
          if (etape != null) etape,
        ].join('\n')),
        isThreeLine: etape != null,
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
            builder: (_) => FicheParcelle(id: doc.id, eleve: eleve),
          ),
        ),
      ),
    );
  }
}
