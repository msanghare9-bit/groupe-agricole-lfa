import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'outils.dart';
import 'planning.dart';

final _plugin = FlutterLocalNotificationsPlugin();

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'rappels',
    "Rappels d'arrosage",
    channelDescription: "Rappels de ton tour d'arrosage",
    importance: Importance.high,
    priority: Priority.high,
  ),
);

Future<void> initNotifications() async {
  try {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Dakar'));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    // Quand l'application est ouverte, Android n'affiche pas lui-même
    // les messages reçus : on les montre nous-mêmes.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      final id = 900000 + DateTime.now().millisecondsSinceEpoch % 90000;
      _plugin.show(id, n.title, n.body, _details);
    });
  } catch (_) {}
}

/// Nom de canal de notification propre à un élève (sans accents ni espaces).
String sujetEleve(String nom) {
  const avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const sans = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buf = StringBuffer('eleve_');
  for (final ch in nom.toLowerCase().split('')) {
    final i = avec.indexOf(ch);
    final c = i >= 0 ? sans[i] : ch;
    buf.write(RegExp(r'[a-z0-9]').hasMatch(c) ? c : '_');
  }
  return buf.toString();
}

/// Abonne le téléphone aux messages du groupe et à ceux de l'élève choisi.
Future<void> abonner(String? nom) async {
  try {
    final m = FirebaseMessaging.instance;
    final prefs = await SharedPreferences.getInstance();
    final ancien = prefs.getString('sujet');
    final nouveau = nom == null ? null : sujetEleve(nom);
    await m.subscribeToTopic('groupe');
    if (ancien != null && ancien != nouveau) {
      await m.unsubscribeFromTopic(ancien);
    }
    if (nouveau != null) {
      await m.subscribeToTopic(nouveau);
      await prefs.setString('sujet', nouveau);
    } else {
      await prefs.remove('sujet');
    }
  } catch (_) {}
}

/// Demande une seule fois les autorisations nécessaires aux rappels.
Future<void> demanderAutorisations(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('autorisations') == true) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text("Rappels d'arrosage"),
      content: const Text(
        "Pour recevoir les rappels de ton tour, autorise les notifications, "
        "puis laisse l'application fonctionner sans restriction de batterie.\n\n"
        "Sur certains téléphones (Tecno, Infinix, Itel), va aussi dans "
        "Paramètres > Applications > Groupe Agricole > Batterie et choisis "
        "« Aucune restriction ».",
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
  try {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
  } catch (_) {}
  await prefs.setBool('autorisations', true);
}

Future<void> _programmer(int id, DateTime quand, String titre, String texte) {
  return _plugin.zonedSchedule(
    id,
    titre,
    texte,
    tz.TZDateTime.from(quand, tz.local),
    _details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> annulerRappels() async {
  try {
    await _plugin.cancelAll();
  } catch (_) {}
}

/// Reprogramme tous les rappels des deux prochaines semaines pour cet élève.
Future<void> planifierRappels(
    Planning p, String nom, List<Map<String, dynamic>> arrosagesRecents) async {
  try {
    await _plugin.cancelAll();
    final maintenant = DateTime.now();
    final lundi = lundiDe(maintenant);
    final creneaux = [
      ...p.semaine(lundi),
      ...p.semaine(lundi.add(const Duration(days: 7))),
    ];
    var id = 1;
    for (final c in creneaux) {
      if (!c.membres.contains(nom)) continue;
      final autres = c.membres.where((m) => m != nom).toList();
      final avec = autres.isEmpty ? '' : ' avec ${autres.join(' et ')}';
      final moment = c.cle == 'matin' ? 'ce matin' : 'ce soir';
      final h = heureLisible(c.debut);

      if (c.cle == 'matin') {
        final veille =
            DateTime(c.debut.year, c.debut.month, c.debut.day - 1, 20);
        if (veille.isAfter(maintenant)) {
          await _programmer(id++, veille, "Demain matin, c'est ton tour",
              'Arrosage à $h$avec.');
        }
      }
      final rappel = c.debut.subtract(const Duration(minutes: 30));
      if (rappel.isAfter(maintenant)) {
        await _programmer(id++, rappel, "C'est bientôt ton tour",
            'Arrosage $moment à $h$avec.');
      }
      final relance = c.debut.add(const Duration(minutes: 90));
      final dejaFait = arrosagesRecents.any((a) {
        final d = tsDe(a['date'])?.toDate();
        return d != null &&
            !d.isBefore(c.debut.subtract(const Duration(hours: 1))) &&
            d.isBefore(c.debut.add(const Duration(hours: 4))) &&
            c.membres.contains(a['eleve']);
      });
      if (relance.isAfter(maintenant) && !dejaFait) {
        await _programmer(id++, relance, 'Arrosage pas encore enregistré',
            "N'oublie pas d'arroser et d'enregistrer l'arrosage de $moment.");
      }
    }
  } catch (_) {}
}
