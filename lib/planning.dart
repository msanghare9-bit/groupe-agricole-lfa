import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'notifs.dart';
import 'outils.dart';

// ---------- Dates ----------

String _d2(int n) => n.toString().padLeft(2, '0');

DateTime lundiDe(DateTime d) {
  final j = DateTime(d.year, d.month, d.day);
  return j.subtract(Duration(days: j.weekday - 1));
}

String cleJour(DateTime d) => '${d.year}-${_d2(d.month)}-${_d2(d.day)}';

String heureLisible(DateTime d) => '${d.hour} h ${_d2(d.minute)}';

const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _joursLongs = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
];

String jourLisible(DateTime d) =>
    '${_joursLongs[d.weekday - 1]} ${d.day}/${_d2(d.month)}';

String cleVersTexte(String cle) {
  final p = cle.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}' : cle;
}

List<int> _lireHeure(dynamic v, int h, int m) {
  if (v is String) {
    final p = v.split(':');
    if (p.length == 2) {
      final a = int.tryParse(p[0]);
      final b = int.tryParse(p[1]);
      if (a != null && b != null) return [a, b];
    }
  }
  return [h, m];
}

// ---------- Modèle ----------

class Creneau {
  Creneau(this.debut, this.cle, this.membres);
  final DateTime debut;
  final String cle; // 'matin' ou 'soir'
  final List<String> membres;
}

class Planning {
  Planning(this.groupes, this.debutRotation, this.matin, this.soir,
      this.semaines, this.remplacements);

  final List<List<String>> groupes;
  final DateTime debutRotation;
  final List<int> matin;
  final List<int> soir;
  final int semaines;
  final List<Map<String, dynamic>> remplacements;

  static Planning? depuis(Map<String, dynamic>? b, Map<String, dynamic>? cf,
      List<Map<String, dynamic>> r) {
    final gs = (b?['groupes'] as List? ?? [])
        .whereType<Map>()
        .map((g) => (g['membres'] as List? ?? []).map((e) => '$e').toList())
        .where((g) => g.isNotEmpty)
        .toList();
    if (gs.isEmpty) return null;
    return Planning(
      gs,
      tsDe(b?['debut'])?.toDate() ?? DateTime.now(),
      _lireHeure(cf?['matin'], 7, 30),
      _lireHeure(cf?['soir'], 17, 30),
      (cf?['semaines'] as num?)?.toInt() ?? 4,
      r,
    );
  }

  /// Les 14 créneaux (matin et soir, du lundi au dimanche) d'une semaine.
  /// Chaque semaine, les créneaux glissent d'un cran entre les groupes.
  List<Creneau> semaine(DateTime lundi) {
    final n = groupes.length;
    final w = lundi.difference(lundiDe(debutRotation)).inDays ~/ 7;
    final res = <Creneau>[];
    for (var s = 0; s < 14; s++) {
      final jour = lundi.add(Duration(days: s ~/ 2));
      final cle = s.isEven ? 'matin' : 'soir';
      final hm = s.isEven ? matin : soir;
      final debut = DateTime(jour.year, jour.month, jour.day, hm[0], hm[1]);
      final g = ((s + w) % n + n) % n;
      final membres = List<String>.from(groupes[g]);
      for (final r in remplacements) {
        if (r['date'] == cleJour(jour) && r['creneau'] == cle) {
          final i = membres.indexOf('${r['absent']}');
          if (i >= 0) membres[i] = '${r['remplacant']}';
        }
      }
      res.add(Creneau(debut, cle, membres));
    }
    return res;
  }

  bool get rotationDue => DateTime.now()
      .isAfter(lundiDe(debutRotation).add(Duration(days: 7 * semaines)));

  String get signature =>
      '$groupes|$debutRotation|$matin|$soir|${remplacements.map((x) => '${x['date']}${x['creneau']}${x['absent']}${x['remplacant']}').join(',')}';
}

/// Rassemble binômes, horaires et remplacements acceptés.
class PlanningBuilder extends StatelessWidget {
  const PlanningBuilder({super.key, required this.builder});
  final Widget Function(BuildContext, Planning?, bool charge) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('binomes').doc('actuel').snapshots(),
      builder: (context, b) => StreamBuilder(
        stream: db.collection('config').doc('planning').snapshots(),
        builder: (context, cf) => StreamBuilder(
          stream: db
              .collection('remplacements')
              .where('statut', isEqualTo: 'accepte')
              .snapshots(),
          builder: (context, r) {
            final charge = b.hasData && cf.hasData && r.hasData;
            if (!charge) return builder(context, null, false);
            return builder(
              context,
              Planning.depuis(b.data!.data(), cf.data!.data(),
                  r.data!.docs.map((d) => d.data()).toList()),
              true,
            );
          },
        ),
      ),
    );
  }
}

// ---------- Prochain tour (accueil élève) et rappels ----------

class ProchainTour extends StatefulWidget {
  const ProchainTour({super.key, required this.nom});
  final String nom;

  @override
  State<ProchainTour> createState() => _ProchainTourState();
}

class _ProchainTourState extends State<ProchainTour> {
  String _signature = '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recents;

  @override
  void initState() {
    super.initState();
    _recents = db
        .collection('arrosages')
        .where('date',
            isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(days: 3))))
        .snapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) demanderAutorisations(context);
    });
  }

  void _planifier(Planning? p, List<Map<String, dynamic>> recents) {
    final sig =
        '${widget.nom}|${p?.signature}|${recents.map((a) => '${a['eleve']}${tsDe(a['date'])?.seconds}').join(',')}';
    if (sig == _signature) return;
    _signature = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (p == null) {
        annulerRappels();
      } else {
        planifierRappels(p, widget.nom, recents);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlanningBuilder(
      builder: (context, p, charge) => StreamBuilder(
        stream: _recents,
        builder: (context, snap) {
          if (!charge || !snap.hasData) return const SizedBox.shrink();
          _planifier(p, snap.data!.docs.map((d) => d.data()).toList());
          if (p == null) return const SizedBox.shrink();
          final maintenant = DateTime.now();
          final lundi = lundiDe(maintenant);
          final prochain = [
            ...p.semaine(lundi),
            ...p.semaine(lundi.add(const Duration(days: 7))),
          ].where((c) =>
              c.membres.contains(widget.nom) &&
              c.debut.add(const Duration(hours: 2)).isAfter(maintenant));
          if (prochain.isEmpty) return const SizedBox.shrink();
          final c = prochain.first;
          final autres = c.membres.where((m) => m != widget.nom).join(' et ');
          return Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Ton prochain tour'),
              subtitle: Text(
                  '${jourLisible(c.debut)} ${c.cle} à ${heureLisible(c.debut)}${autres.isEmpty ? '' : '\navec $autres'}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PagePlanning(nom: widget.nom)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BandeauAnnonce extends StatelessWidget {
  const BandeauAnnonce({super.key, required this.ouvrir});
  final VoidCallback ouvrir;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db
          .collection('annonces')
          .orderBy('date', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        final d = docs.first.data();
        final ts = tsDe(d['date']);
        if (ts == null || DateTime.now().difference(ts.toDate()).inDays > 7) {
          return const SizedBox.shrink();
        }
        return Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: Text('${d['titre'] ?? ''}'),
            subtitle: Text(dateLisible(ts)),
            trailing: const Icon(Icons.chevron_right),
            onTap: ouvrir,
          ),
        );
      },
    );
  }
}

// ---------- Emploi du temps ----------

class PagePlanning extends StatefulWidget {
  const PagePlanning({super.key, required this.nom});
  final String nom;

  @override
  State<PagePlanning> createState() => _PagePlanningState();
}

class _PagePlanningState extends State<PagePlanning> {
  int _decalage = 0;

  Future<void> _demander(Creneau c) async {
    final el = await db.collection('eleves').orderBy('nom').get();
    final noms = el.docs
        .map((d) => '${d.data()['nom'] ?? ''}')
        .where((n) => n.isNotEmpty && !c.membres.contains(n))
        .toList();
    if (!mounted) return;
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Qui peut te remplacer ?'),
              subtitle: Text('${jourLisible(c.debut)} ${c.cle}'),
            ),
            for (final n in noms)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(n),
                onTap: () => Navigator.pop(ctx, n),
              ),
          ],
        ),
      ),
    );
    if (choix == null) return;
    ecrire(db.collection('remplacements').add({
      'date': cleJour(c.debut),
      'creneau': c.cle,
      'absent': widget.nom,
      'remplacant': choix,
      'statut': 'demande',
      'cree': Timestamp.now(),
    }));
    if (mounted) message(context, 'Demande envoyée au responsable');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Emploi du temps')),
      body: PlanningBuilder(
        builder: (context, p, charge) {
          if (!charge) {
            return const Center(child: CircularProgressIndicator());
          }
          if (p == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Les binômes ne sont pas encore formés.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final lundi =
              lundiDe(DateTime.now()).add(Duration(days: 7 * _decalage));
          final cr = p.semaine(lundi);
          final monGroupe = p.groupes.firstWhere(
              (g) => g.contains(widget.nom),
              orElse: () => <String>[]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Cette semaine'),
                    selected: _decalage == 0,
                    onSelected: (_) => setState(() => _decalage = 0),
                  ),
                  ChoiceChip(
                    label: const Text('Semaine prochaine'),
                    selected: _decalage == 1,
                    onSelected: (_) => setState(() => _decalage = 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (monGroupe.isNotEmpty)
                Text('Ton binôme : ${monGroupe.join(' et ')}',
                    style: theme.textTheme.titleMedium),
              Text(
                'Semaine du ${lundi.day}/${_d2(lundi.month)} · matin ${p.matin[0]} h ${_d2(p.matin[1])}, soir ${p.soir[0]} h ${_d2(p.soir[1])}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (var j = 0; j < 7; j++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Center(child: Text(_jours[j])),
                        ),
                        Expanded(child: _case(context, cr[2 * j])),
                        const SizedBox(width: 6),
                        Expanded(child: _case(context, cr[2 * j + 1])),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Touche une de tes cases pour demander un remplacement.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _case(BuildContext context, Creneau c) {
    final scheme = Theme.of(context).colorScheme;
    final moi = c.membres.contains(widget.nom);
    final futur = c.debut.isAfter(DateTime.now());
    return Material(
      color: moi ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: moi && futur ? () => _demander(c) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            c.membres.join('\n'),
            style: TextStyle(
              fontSize: 12,
              color: moi ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: moi ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Binômes (responsable) ----------

List<String> pairesDe(List<List<String>> gs) {
  final r = <String>[];
  for (final g in gs) {
    for (var i = 0; i < g.length; i++) {
      for (var j = i + 1; j < g.length; j++) {
        final a = [g[i], g[j]]..sort();
        r.add(a.join('|'));
      }
    }
  }
  return r;
}

/// Forme des binômes (un trinôme si le nombre est impair) en évitant
/// autant que possible les paires déjà formées.
List<List<String>> meilleursGroupes(List<String> noms, Set<String> deja) {
  final rnd = Random();
  List<List<String>> meilleur = [];
  var score = 1 << 30;
  for (var essai = 0; essai < 400; essai++) {
    final l = List<String>.from(noms)..shuffle(rnd);
    final gs = <List<String>>[];
    for (var i = 0; i + 1 < l.length; i += 2) {
      gs.add([l[i], l[i + 1]]);
    }
    if (l.length.isOdd) gs.last.add(l.last);
    final s = pairesDe(gs).where(deja.contains).length;
    if (s < score) {
      score = s;
      meilleur = gs;
      if (s == 0) break;
    }
  }
  return meilleur;
}

Map<String, dynamic> notification(String cible, String titre, String texte) => {
      'cible': cible,
      'titre': titre,
      'texte': texte,
      'envoye': false,
      'date': Timestamp.now(),
    };

class GestionBinomes extends StatelessWidget {
  const GestionBinomes({super.key});

  Future<void> _former(BuildContext context, bool premier) async {
    final el = await db.collection('eleves').get();
    final noms = el.docs
        .map((d) => '${d.data()['nom'] ?? ''}')
        .where((n) => n.isNotEmpty)
        .toList();
    if (!context.mounted) return;
    if (noms.length < 2) {
      message(context, 'Il faut au moins deux élèves.');
      return;
    }
    final h = await db.collection('binomes').doc('historique').get();
    final deja =
        Set<String>.from((h.data()?['paires'] as List? ?? []).map((e) => '$e'));
    var proposition = meilleursGroupes(noms, deja);
    if (!context.mounted) return;
    final quand = premier ? 'cette semaine' : 'lundi prochain';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nouveaux binômes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final g in proposition)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• ${g.join(' et ')}'),
                  ),
                const SizedBox(height: 8),
                Text('Ils commenceront $quand.',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  setD(() => proposition = meilleursGroupes(noms, deja)),
              child: const Text('Mélanger'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final lundi = lundiDe(DateTime.now());
    final debut = premier ? lundi : lundi.add(const Duration(days: 7));
    final batch = db.batch();
    batch.set(db.collection('binomes').doc('actuel'), {
      'groupes': [
        for (final g in proposition) {'membres': g}
      ],
      'debut': Timestamp.fromDate(debut),
    });
    batch.set(
      db.collection('binomes').doc('historique'),
      {'paires': FieldValue.arrayUnion(pairesDe(proposition))},
      SetOptions(merge: true),
    );
    for (final g in proposition) {
      for (final m in g) {
        final autres = g.where((x) => x != m).join(' et ');
        batch.set(
          db.collection('notifications').doc(),
          notification(sujetEleve(m), 'Nouveau binôme',
              'À partir de $quand, tu arroses avec $autres.'),
        );
      }
    }
    ecrire(batch.commit());
    if (context.mounted) message(context, 'Nouveaux binômes enregistrés');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Binômes')),
      body: PlanningBuilder(
        builder: (context, p, charge) {
          if (!charge) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (p == null)
                const Text('Aucun binôme formé pour le moment.')
              else ...[
                Text(
                  'Depuis le ${jourLisible(p.debutRotation)} · changement toutes les ${p.semaines} semaines',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (p.rotationDue)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Il est temps de former de nouveaux binômes.'),
                    ),
                  ),
                for (final g in p.groupes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group_outlined),
                    title: Text(g.join(' et ')),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _former(context, p == null),
                icon: const Icon(Icons.shuffle),
                label: const Text('Former de nouveaux binômes'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Demandes de remplacement (responsable) ----------

class DemandesRemplacement extends StatelessWidget {
  const DemandesRemplacement({super.key});

  void _repondre(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> d, bool accepte) {
    final r = d.data();
    final absent = '${r['absent']}';
    final remplacant = '${r['remplacant']}';
    final quand = '${cleVersTexte('${r['date']}')} (${r['creneau']})';
    final batch = db.batch();
    batch.update(d.reference, {'statut': accepte ? 'accepte' : 'refuse'});
    if (accepte) {
      batch.set(
          db.collection('notifications').doc(),
          notification(sujetEleve(absent), 'Remplacement accepté',
              '$remplacant arrosera à ta place le $quand.'));
      batch.set(
          db.collection('notifications').doc(),
          notification(sujetEleve(remplacant), 'Tu remplaces $absent',
              'Arrosage le $quand.'));
    } else {
      batch.set(
          db.collection('notifications').doc(),
          notification(sujetEleve(absent), 'Remplacement refusé',
              'Ton tour du $quand est maintenu.'));
    }
    ecrire(batch.commit());
    message(context, accepte ? 'Remplacement accepté' : 'Demande refusée');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes de remplacement')),
      body: StreamBuilder(
        stream: db
            .collection('remplacements')
            .where('statut', isEqualTo: 'demande')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucune demande en attente.'));
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final d in docs)
                Card(
                  child: ListTile(
                    title: Text('${d.data()['absent']} → ${d.data()['remplacant']}'),
                    subtitle: Text(
                        '${cleVersTexte('${d.data()['date']}')} · ${d.data()['creneau']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Refuser',
                          icon: const Icon(Icons.close),
                          onPressed: () => _repondre(context, d, false),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Accepter',
                          icon: const Icon(Icons.check),
                          onPressed: () => _repondre(context, d, true),
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

// ---------- Réglages du planning (responsable) ----------

class ReglagesPlanning extends StatefulWidget {
  const ReglagesPlanning({super.key});

  @override
  State<ReglagesPlanning> createState() => _ReglagesPlanningState();
}

class _ReglagesPlanningState extends State<ReglagesPlanning> {
  TimeOfDay _matin = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _soir = const TimeOfDay(hour: 17, minute: 30);
  int _semaines = 4;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    db.collection('config').doc('planning').get().then((s) {
      final d = s.data();
      final m = _lireHeure(d?['matin'], 7, 30);
      final so = _lireHeure(d?['soir'], 17, 30);
      if (!mounted) return;
      setState(() {
        _matin = TimeOfDay(hour: m[0], minute: m[1]);
        _soir = TimeOfDay(hour: so[0], minute: so[1]);
        final w = (d?['semaines'] as num?)?.toInt() ?? 4;
        _semaines = const [2, 3, 4, 6, 8].contains(w) ? w : 4;
        _charge = true;
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _charge = true);
    });
  }

  String _txt(TimeOfDay t) => '${t.hour} h ${_d2(t.minute)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages du planning')),
      body: !_charge
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Arrosage du matin'),
                  trailing: Text(_txt(_matin)),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _matin);
                    if (t != null) setState(() => _matin = t);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Arrosage du soir'),
                  trailing: Text(_txt(_soir)),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _soir);
                    if (t != null) setState(() => _soir = t);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Changer les binômes toutes les'),
                  trailing: DropdownButton<int>(
                    value: _semaines,
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('2 semaines')),
                      DropdownMenuItem(value: 3, child: Text('3 semaines')),
                      DropdownMenuItem(value: 4, child: Text('4 semaines')),
                      DropdownMenuItem(value: 6, child: Text('6 semaines')),
                      DropdownMenuItem(value: 8, child: Text('8 semaines')),
                    ],
                    onChanged: (v) => setState(() => _semaines = v ?? 4),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ecrire(db.collection('config').doc('planning').set({
                      'matin': '${_d2(_matin.hour)}:${_d2(_matin.minute)}',
                      'soir': '${_d2(_soir.hour)}:${_d2(_soir.minute)}',
                      'semaines': _semaines,
                    }, SetOptions(merge: true)));
                    message(context, 'Réglages enregistrés');
                    Navigator.pop(context);
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
    );
  }
}

