import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'admin.dart';
import 'contenus.dart';
import 'fiche.dart';
import 'miseajour.dart';
import 'outils.dart';
import 'planning.dart';
import 'theme.dart';

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

String _aujourdhui() {
  final d = DateTime.now();
  final j = _jours[d.weekday - 1];
  return '${j[0].toUpperCase()}${j.substring(1)} ${d.day} ${_mois[d.month - 1]}';
}

void _ouvrir(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

// ---------- Structure : barre de navigation ----------

class Accueil extends StatefulWidget {
  const Accueil({super.key, required this.nom, required this.onChangerNom});
  final String nom;
  final VoidCallback onChangerNom;

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  int _onglet = 0;

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    final pages = [
      _Jardin(nom: widget.nom),
      PagePlanning(nom: widget.nom),
      const SizedBox.shrink(),
      const ListeLecons(),
      PageMoi(nom: widget.nom, onChangerNom: widget.onChangerNom),
    ];
    return Scaffold(
      body: IndexedStack(index: _onglet, children: pages),
      floatingActionButton: admin && _onglet == 0
          ? FloatingActionButton.extended(
              onPressed: () => formulaireParcelle(context),
              icon: const Icon(Icons.add),
              label: const Text('Parcelle'),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Lf.bord)),
        ),
        child: NavigationBar(
          height: 74,
          selectedIndex: _onglet,
          onDestinationSelected: (i) {
            if (i == 2) {
              nouvelleRemarque(context, widget.nom);
            } else {
              setState(() => _onglet = i);
            }
          },
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.yard_outlined),
                selectedIcon: Icon(Icons.yard),
                label: 'Jardin'),
            const NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Planning'),
            NavigationDestination(
              icon: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: Lf.vert, shape: BoxShape.circle),
                child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 22),
              ),
              label: 'Remarque',
            ),
            const NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'Leçons'),
            const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Moi'),
          ],
        ),
      ),
    );
  }
}

// ---------- Onglet Jardin ----------

class _Jardin extends StatelessWidget {
  const _Jardin({required this.nom});
  final String nom;

  void _arroserTour(BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      message(context, "Aucune parcelle pour l'instant.");
      return;
    }
    final choisies = <String>{
      for (final d in docs)
        if (etatDe(d.data()) != Etat.arrosee) d.id
    };
    if (choisies.isEmpty) choisies.addAll(docs.map((d) => d.id));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quelles parcelles as-tu arrosées ?', style: Lf.serif(size: 20)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in docs)
                        CheckboxListTile(
                          value: choisies.contains(d.id),
                          activeColor: Lf.vert,
                          contentPadding: EdgeInsets.zero,
                          title: Text([
                            '${d.data()['culture'] ?? ''}',
                            '${d.data()['nom'] ?? ''}'
                          ].where((x) => x.isNotEmpty).join(' · ')),
                          subtitle: Text(libelle(etatDe(d.data()))),
                          onChanged: (v) => setS(() =>
                              v == true ? choisies.add(d.id) : choisies.remove(d.id)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Lf.orange),
                    onPressed: choisies.isEmpty
                        ? null
                        : () {
                            final maintenant = Timestamp.now();
                            final batch = db.batch();
                            for (final d in docs.where((d) => choisies.contains(d.id))) {
                              batch.set(db.collection('arrosages').doc(), {
                                'parcelleId': d.id,
                                'parcelle': d.data()['nom'] ?? '',
                                'eleve': nom,
                                'date': maintenant,
                              });
                              batch.update(d.reference,
                                  {'dernierArrosage': maintenant, 'dernierPar': nom});
                            }
                            ecrire(batch.commit());
                            Navigator.pop(ctx);
                            message(context,
                                choisies.length == 1 ? 'Arrosage enregistré' : '${choisies.length} arrosages enregistrés');
                          },
                    icon: const Icon(Icons.water_drop),
                    label: const Text("J'ai arrosé"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder(
        stream: db.collection('parcelles').orderBy('nom').snapshots(includeMetadataChanges: true),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          final meta = snap.data?.metadata;
          final haut = MediaQuery.of(context).padding.top + 236.0;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: haut,
                    child: _Bandeau(
                      nom: nom,
                      admin: admin,
                      sync: meta == null
                          ? Icons.cloud_queue
                          : meta.hasPendingWrites
                              ? Icons.cloud_upload_outlined
                              : meta.isFromCache
                                  ? Icons.cloud_off_outlined
                                  : Icons.cloud_done_outlined,
                    ),
                  ),
                  _Centre(
                    child: Padding(
                      padding: EdgeInsets.only(top: haut - 48, left: 14, right: 14),
                      child: ProchainTour(
                        nom: nom,
                        admin: admin,
                        onArroser: admin ? null : () => _arroserTour(context, docs),
                      ),
                    ),
                  ),
                ],
              ),
              _Centre(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      const BandeauMiseAJour(),
                      BandeauAnnonce(ouvrir: () => _ouvrir(context, const ListeAnnonces())),
                      _EtatJardin(docs: docs, admin: admin, charge: snap.hasData),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _Raccourci(
                              icone: Icons.newspaper_outlined,
                              titre: 'Actualités',
                              fond: Lf.vertClair,
                              couleur: Lf.vert,
                              page: const ListeActualites(),
                            ),
                          ),
                          Expanded(
                            child: _Raccourci(
                              icone: Icons.menu_book_outlined,
                              titre: 'Leçons',
                              fond: Lf.orangeClair,
                              couleur: Lf.orangeFonce,
                              page: const ListeLecons(),
                            ),
                          ),
                          Expanded(
                            child: _Raccourci(
                              icone: Icons.campaign_outlined,
                              titre: 'Annonces',
                              fond: Lf.sable,
                              couleur: Lf.brun,
                              page: const ListeAnnonces(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('Parcelles', style: Lf.serif(size: 20)),
                      const SizedBox(height: 10),
                      if (snap.hasError)
                        Text('Erreur : ${snap.error}')
                      else if (!snap.hasData)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (docs.isEmpty)
                        _Vide(admin: admin)
                      else
                        LayoutBuilder(
                          builder: (context, c) {
                            final largeur = (c.maxWidth - 10) / 2;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final d in docs)
                                  SizedBox(
                                    width: largeur,
                                    child: _CarteParcelle(doc: d, eleve: nom),
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Centre extends StatelessWidget {
  const _Centre({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: child,
        ),
      );
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.nom, required this.admin, required this.sync});
  final String nom;
  final bool admin;
  final IconData sync;

  @override
  Widget build(BuildContext context) {
    final prenom = nom.trim().split(' ').first;
    return Container(
      color: Lf.vert,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: PaysageJardin())),
          _Centre(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FeuilleLogo(taille: 28),
                      const SizedBox(width: 10),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'LFA', style: Lf.serif(size: 20, color: Lf.creme, weight: FontWeight.w600)),
                          TextSpan(text: 'RM', style: Lf.serif(size: 20, color: const Color(0xFFF2A65A), weight: FontWeight.w600)),
                        ]),
                        style: const TextStyle(letterSpacing: 3),
                      ),
                      const Spacer(),
                      Icon(sync, color: const Color(0xFFBFD9C5), size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Lf.devise,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBFD9C5), letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    admin ? 'Espace responsable' : 'Bonjour $prenom',
                    style: Lf.serif(size: 27, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const _LigneDate(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneDate extends StatelessWidget {
  const _LigneDate();

  static Future<double?>? _meteo;

  static Future<double?> _charger() async {
    try {
      final r = await http
          .get(Uri.parse(
              'https://api.open-meteo.com/v1/forecast?latitude=15.37&longitude=-16.45&current=temperature_2m&timezone=Africa%2FDakar'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final t = (jsonDecode(r.body)['current']?['temperature_2m'] as num?)?.toDouble();
      return t;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _meteo ??= _charger();
    const style = TextStyle(fontSize: 14, color: Color(0xFFCFE3D4));
    return FutureBuilder<double?>(
      future: _meteo,
      builder: (context, snap) {
        final t = snap.data;
        var texte = _aujourdhui();
        if (t != null) {
          texte += ' · ${t.round()} °C';
          if (t >= 30) texte += ', pensez à bien arroser';
        }
        return Text(texte, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

class _EtatJardin extends StatelessWidget {
  const _EtatJardin({required this.docs, required this.admin, required this.charge});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool admin;
  final bool charge;

  @override
  Widget build(BuildContext context) {
    final n = docs.length;
    final ok = docs.where((d) => etatDe(d.data()) == Etat.arrosee).length;
    final afaire = docs.where((d) => etatDe(d.data()) == Etat.aArroser).length;
    final retard = n - ok - afaire;
    Widget point(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF6B6455))),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 66,
              height: 66,
              child: CustomPaint(
                painter: Jauge(n == 0 ? 0 : ok / n),
                child: Center(child: Text(charge ? '$ok/$n' : '…', style: Lf.serif(size: 16))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Le jardin aujourd'hui", style: Lf.serif(size: 17)),
                  const SizedBox(height: 6),
                  if (n == 0)
                    Text(admin ? 'Ajoute ta première parcelle.' : 'Aucune parcelle pour le moment.',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6B6455)))
                  else
                    Wrap(spacing: 10, runSpacing: 4, children: [
                      point(Lf.feuille, '$ok arrosée${ok > 1 ? 's' : ''}'),
                      if (afaire > 0) point(Lf.orange, '$afaire à faire'),
                      if (retard > 0) point(Lf.rouge, '$retard en retard'),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Raccourci extends StatelessWidget {
  const _Raccourci({
    required this.icone,
    required this.titre,
    required this.fond,
    required this.couleur,
    required this.page,
  });
  final IconData icone;
  final String titre;
  final Color fond;
  final Color couleur;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _ouvrir(context, page),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(17)),
              child: Icon(icone, color: couleur, size: 24),
            ),
            const SizedBox(height: 6),
            Text(titre, style: const TextStyle(fontSize: 13, color: Color(0xFF4A463D))),
          ],
        ),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({required this.admin});
  final bool admin;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.grass, color: Lf.feuille, size: 36),
              const SizedBox(height: 8),
              Text(
                admin
                    ? 'Crée la première parcelle avec le bouton « Parcelle ».'
                    : "Le responsable n'a pas encore créé de parcelle.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

IconData _iconeEtape(String? e) => switch (e) {
      'Semis' => Icons.grain,
      'Levée' => Icons.grass,
      'Croissance' => Icons.eco_outlined,
      'Floraison' => Icons.local_florist_outlined,
      'Fructification' => Icons.spa_outlined,
      'Récolte' => Icons.agriculture_outlined,
      _ => Icons.yard_outlined,
    };

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
    final rang = etape == null ? 0 : etapes.indexOf(etape) + 1;
    final (fond, texte) = switch (etat) {
      Etat.arrosee => (Lf.vertClair, Lf.vert),
      Etat.aArroser => (Lf.orangeClair, Lf.orangeFonce),
      Etat.enRetard => (Lf.rougeClair, Lf.rouge),
    };
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Lf.bord, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _ouvrir(context, FicheParcelle(id: doc.id, eleve: eleve)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
                    child: Icon(_iconeEtape(etape), color: texte, size: 20),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(999)),
                      child: Text(libelle(etat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: texte, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(culture.isEmpty ? nomP : culture,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Lf.serif(size: 16)),
              Text(
                [if (culture.isNotEmpty) nomP, (etape ?? depuis(tsDe(p['dernierArrosage']))).toLowerCase()]
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Lf.taupe),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  for (var i = 0; i < etapes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < rang ? Lf.feuille : const Color(0xFFE9E3D6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (etat != Etat.arrosee) ...[
                const SizedBox(height: 10),
                Material(
                  color: Lf.orangeClair,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => enregistrerArrosage(context, doc.id, nomP, eleve),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.water_drop, size: 16, color: Lf.orangeFonce),
                          SizedBox(width: 4),
                          Text("J'ai arrosé",
                              style: TextStyle(fontSize: 13, color: Lf.orangeFonce, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Bandeau de mise à jour ----------

class BandeauMiseAJour extends StatelessWidget {
  const BandeauMiseAJour({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('config').doc('app').snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null || kIsWeb) return const SizedBox.shrink();
        final version = (d['version'] as num?)?.toInt() ?? 0;
        final lien = d['lien'] as String? ?? '';
        if (version <= versionLocale || lien.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          color: Lf.vert,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ListTile(
            leading: const Icon(Icons.system_update_outlined, color: Colors.white),
            title: const Text('Mise à jour disponible',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Touche pour installer la nouvelle version.',
                style: TextStyle(color: Color(0xFFCFE3D4))),
            trailing: const Icon(Icons.chevron_right, color: Colors.white),
            onTap: () => installerMiseAJour(context, lien),
          ),
        );
      },
    );
  }
}

// ---------- Onglet Moi ----------

class PageMoi extends StatelessWidget {
  const PageMoi({super.key, required this.nom, required this.onChangerNom});
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

  Widget _groupe(String titre, List<Widget> lignes) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(titre,
                  style: const TextStyle(fontSize: 13, color: Lf.taupe, fontWeight: FontWeight.w600)),
            ),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < lignes.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    lignes[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _ligne(BuildContext context, IconData icone, String titre,
          {Widget? page, VoidCallback? action, Color couleur = Lf.vert}) =>
      ListTile(
        leading: Icon(icone, color: couleur),
        title: Text(titre),
        trailing: const Icon(Icons.chevron_right, color: Lf.taupe),
        onTap: action ?? () => _ouvrir(context, page!),
      );

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Moi')),
      body: _Centre(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: admin ? Lf.orangeClair : Lf.vertClair,
                      child: Text(initiales(nom),
                          style: TextStyle(
                              color: admin ? Lf.orangeFonce : Lf.vert,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nom, style: Lf.serif(size: 19)),
                          Text(admin ? 'Responsable du groupe' : 'Membre du Groupe Agricole',
                              style: const TextStyle(color: Lf.taupe)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (admin) ...[
              _groupe('Le groupe', [
                _ligne(context, Icons.groups_outlined, 'Élèves', page: const GestionEleves()),
                _ligne(context, Icons.diversity_3_outlined, 'Binômes', page: const GestionBinomes()),
                _ligne(context, Icons.swap_horiz, 'Demandes de remplacement', page: const DemandesRemplacement()),
                _ligne(context, Icons.schedule_outlined, 'Réglages du planning', page: const ReglagesPlanning()),
              ]),
              _groupe('Publications', [
                _ligne(context, Icons.campaign_outlined, 'Annonces', page: const ListeAnnonces()),
                _ligne(context, Icons.newspaper_outlined, 'Actualités', page: const ListeActualites()),
                _ligne(context, Icons.photo_library_outlined, 'Remarques et photos', page: const ToutesRemarques()),
                _ligne(context, Icons.water_drop_outlined, 'Journal des arrosages', page: const JournalArrosages()),
              ]),
              _groupe('Compte', [
                _ligne(context, Icons.logout, 'Se déconnecter',
                    action: () => _deconnecter(context), couleur: Lf.rouge),
              ]),
            ] else ...[
              _groupe('Mon compte', [
                _ligne(context, Icons.switch_account_outlined, "Changer d'élève", action: onChangerNom),
                _ligne(context, Icons.admin_panel_settings_outlined, 'Espace responsable',
                    page: const ConnexionResponsable()),
              ]),
              _groupe('Le jardin', [
                _ligne(context, Icons.newspaper_outlined, 'Actualités', page: const ListeActualites()),
                _ligne(context, Icons.campaign_outlined, 'Annonces', page: const ListeAnnonces()),
              ]),
            ],
            const SizedBox(height: 32),
            const Center(child: FeuilleLogo(taille: 34, couleur: Lf.feuille, nervure: Color(0xFFA9CDB1))),
            const SizedBox(height: 8),
            Center(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'LFA', style: Lf.serif(size: 18, color: Lf.vert, weight: FontWeight.w600)),
                TextSpan(text: 'RM', style: Lf.serif(size: 18, color: Lf.orange, weight: FontWeight.w600)),
              ]), style: const TextStyle(letterSpacing: 3)),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(Lf.devise,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Lf.taupe, letterSpacing: 0.4)),
            ),
            if (!kIsWeb && versionNom.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: Text('Version $versionNom ($versionLocale)',
                      style: const TextStyle(fontSize: 11, color: Lf.taupe)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
