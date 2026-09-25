import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'outils.dart';
import 'planning.dart';

Uint8List? _decoder(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  try {
    return base64Decode(v);
  } catch (_) {
    return null;
  }
}

// ---------- Éditeur commun (actualités et leçons) ----------

class EditeurPublication extends StatefulWidget {
  const EditeurPublication({
    super.key,
    required this.collection,
    this.id,
    this.actuelle,
  });
  final String collection; // 'actualites' ou 'lecons'
  final String? id;
  final Map<String, dynamic>? actuelle;

  @override
  State<EditeurPublication> createState() => _EditeurPublicationState();
}

class _EditeurPublicationState extends State<EditeurPublication> {
  late final TextEditingController _titre;
  late final TextEditingController _texte;
  Uint8List? _image;
  bool _occupe = false;

  bool get _lecon => widget.collection == 'lecons';

  @override
  void initState() {
    super.initState();
    _titre = TextEditingController(
        text: widget.actuelle?['titre'] as String? ?? '');
    _texte = TextEditingController(
        text: widget.actuelle?['texte'] as String? ?? '');
    _image = _decoder(widget.actuelle?['image']);
  }

  @override
  void dispose() {
    _titre.dispose();
    _texte.dispose();
    super.dispose();
  }

  Future<void> _prendre(ImageSource source) async {
    setState(() => _occupe = true);
    try {
      final f = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 60,
      );
      if (f != null) {
        final b = await f.readAsBytes();
        if (!mounted) return;
        if (b.length > 600000) {
          message(context, 'Image trop lourde, choisis-en une autre.');
        } else {
          setState(() => _image = b);
        }
      }
    } catch (_) {
      if (mounted) message(context, "Impossible d'ouvrir l'image.");
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  void _publier() {
    final titre = _titre.text.trim();
    final texte = _texte.text.trim();
    if (titre.isEmpty) {
      message(context, 'Ajoute un titre.');
      return;
    }
    final img = _image;
    final donnees = <String, dynamic>{
      'titre': titre,
      'texte': texte,
      'image': img == null ? '' : base64Encode(img),
    };
    final col = db.collection(widget.collection);
    if (widget.id == null) {
      final batch = db.batch();
      batch.set(col.doc(), {...donnees, 'date': Timestamp.now()});
      batch.set(
        db.collection('notifications').doc(),
        notification('groupe',
            _lecon ? 'Nouvelle leçon' : 'Actualité du jardin', titre),
      );
      ecrire(batch.commit());
      message(context, 'Publié');
    } else {
      ecrire(col.doc(widget.id).update(donnees));
      message(context, 'Modifications enregistrées');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    final nouveau = widget.id == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(nouveau
            ? (_lecon ? 'Nouvelle leçon' : 'Nouvelle actualité')
            : 'Modifier'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Titre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          if (img != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(img),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _image = null),
              icon: const Icon(Icons.hide_image_outlined),
              label: const Text("Retirer l'image"),
            ),
          ],
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
          const SizedBox(height: 12),
          TextField(
            controller: _texte,
            minLines: _lecon ? 12 : 5,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _lecon ? 'Contenu de la leçon' : 'Texte',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _occupe ? null : _publier,
            icon: const Icon(Icons.send),
            label: Text(nouveau ? 'Publier' : 'Enregistrer'),
          ),
          if (nouveau)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Les élèves recevront une notification dans la demi-heure.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _gerer(BuildContext context, String collection,
    QueryDocumentSnapshot<Map<String, dynamic>> d) async {
  final choix = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Modifier'),
            onTap: () => Navigator.pop(ctx, 'modifier'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Supprimer'),
            onTap: () => Navigator.pop(ctx, 'supprimer'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choix == 'modifier') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditeurPublication(
            collection: collection, id: d.id, actuelle: d.data()),
      ),
    );
  } else if (choix == 'supprimer') {
    if (await confirmer(context, 'Supprimer « ${d.data()['titre']} » ?')) {
      ecrire(d.reference.delete());
    }
  }
}

// ---------- Actualités ----------

class ListeActualites extends StatelessWidget {
  const ListeActualites({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Actualités du jardin')),
      body: StreamBuilder(
        stream: db
            .collection('actualites')
            .orderBy('date', descending: true)
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
            return const Center(child: Text('Aucune actualité pour le moment.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            children: [
              for (final d in docs)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onLongPress:
                        admin ? () => _gerer(context, 'actualites', d) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_decoder(d.data()['image']) != null)
                          Image.memory(_decoder(d.data()['image'])!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              gaplessPlayback: true),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${d.data()['titre'] ?? ''}',
                                  style: theme.titleMedium),
                              if (tsDe(d.data()['date']) != null)
                                Text(dateCourte(tsDe(d.data()['date'])!),
                                    style: theme.bodySmall),
                              if ('${d.data()['texte'] ?? ''}'.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('${d.data()['texte']}'),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const EditeurPublication(collection: 'actualites')),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Actualité'),
            )
          : null,
    );
  }
}

// ---------- Leçons ----------

class ListeLecons extends StatelessWidget {
  const ListeLecons({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = estAdmin.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Leçons')),
      body: StreamBuilder(
        stream:
            db.collection('lecons').orderBy('date', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucune leçon pour le moment.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
            children: [
              for (final d in docs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text('${d.data()['titre'] ?? ''}'),
                    subtitle: tsDe(d.data()['date']) != null
                        ? Text(dateCourte(tsDe(d.data()['date'])!))
                        : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PageLecon(id: d.id)),
                    ),
                    onLongPress:
                        admin ? () => _gerer(context, 'lecons', d) : null,
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const EditeurPublication(collection: 'lecons')),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Leçon'),
            )
          : null,
    );
  }
}

class PageLecon extends StatelessWidget {
  const PageLecon({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('lecons').doc(id).snapshots(),
      builder: (context, snap) {
        final l = snap.data?.data();
        if (snap.hasData && l == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Cette leçon a été supprimée.')),
          );
        }
        if (l == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final image = _decoder(l['image']);
        final theme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Leçon'),
            actions: estAdmin.value
                ? [
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditeurPublication(
                              collection: 'lecons', id: id, actuelle: l),
                        ),
                      ),
                    ),
                  ]
                : null,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${l['titre'] ?? ''}', style: theme.headlineSmall),
              if (tsDe(l['date']) != null)
                Text(dateCourte(tsDe(l['date'])!), style: theme.bodySmall),
              const SizedBox(height: 16),
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(image),
                ),
                const SizedBox(height: 16),
              ],
              SelectableText('${l['texte'] ?? ''}',
                  style: theme.bodyLarge?.copyWith(height: 1.5)),
            ],
          ),
        );
      },
    );
  }
}
