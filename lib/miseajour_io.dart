import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'outils.dart';

const _canal = MethodChannel('lfarm/installateur');

/// Télécharge la nouvelle version puis ouvre l'écran d'installation d'Android.
/// En cas d'échec, le lien s'ouvre dans le navigateur.
Future<void> installerMiseAJour(BuildContext context, String lien) async {
  final progression = ValueNotifier<double?>(null);
  var annule = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Mise à jour'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progression,
        builder: (_, v, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Téléchargement de la nouvelle version…'),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: v),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            annule = true;
            Navigator.pop(ctx);
          },
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
  try {
    final dossier = await _canal.invokeMethod<String>('dossier');
    final fichier = File('$dossier/LFARM.apk');
    final client = HttpClient();
    final requete = await client.getUrl(Uri.parse(lien));
    final reponse = await requete.close();
    if (reponse.statusCode != 200) {
      throw HttpException('Code ${reponse.statusCode}');
    }
    final total = reponse.contentLength;
    var recu = 0;
    final sortie = fichier.openWrite();
    await for (final bloc in reponse) {
      if (annule) break;
      sortie.add(bloc);
      recu += bloc.length;
      if (total > 0) progression.value = recu / total;
    }
    await sortie.close();
    client.close();
    if (annule) return;
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await _canal.invokeMethod('installer', {'chemin': fichier.path});
  } catch (_) {
    if (annule) return;
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      message(context, 'Ouverture du téléchargement dans le navigateur…');
    }
    await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
  }
}
