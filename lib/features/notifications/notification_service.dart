// Integração com o flutter_local_notifications: canais, permissões,
// agendamento (`zonedSchedule` + `exactAllowWhileIdle`) e ações.
//
// As ações "Concluir" e "Adiar 1h" rodam sem abrir o app: o plugin chama
// [notificationActionBackground] num isolate de segundo plano, que abre o
// banco, aplica a ação e reagenda (ver background_actions.dart).
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/notification_plan.dart';
import 'background_actions.dart';
import 'notification_scheduler.dart';

const channelReminders = 'lembretes';
const channelSummary = 'resumo_diario';
const actionComplete = 'concluir';
const actionSnooze = 'adiar';

/// Fuso padrão se o aparelho não informar um conhecido.
const defaultTimezone = 'America/Sao_Paulo';

bool _tzReady = false;

/// Carrega a base de fusos e usa o fuso do aparelho.
Future<void> initTimezone() async {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  var name = defaultTimezone;
  try {
    name = (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object {
    name = defaultTimezone;
  }
  try {
    tz.setLocalLocation(tz.getLocation(name));
  } on Object {
    tz.setLocalLocation(tz.getLocation(defaultTimezone));
  }
  _tzReady = true;
}

class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;

  AndroidFlutterLocalNotificationsPlugin? get android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Inicializa o plugin e cria os canais. [onTap] recebe o payload quando
  /// o app está aberto (ou em segundo plano) e a notificação é tocada.
  Future<void> initialize({void Function(NotificationResponse r)? onTap}) async {
    await initTimezone();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notificacao')),
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelReminders,
      'Lembretes',
      description: 'Lembretes de tarefas e eventos',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelSummary,
      'Resumo diário',
      description: 'O resumo do dia, de manhã',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    ));
  }

  /// Payload da notificação que abriu o app (app estava fechado).
  Future<String?> launchPayload() async {
    final d = await plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp ?? false) return d!.notificationResponse?.payload;
    return null;
  }

  Future<bool> notificationsEnabled() async => await android?.areNotificationsEnabled() ?? false;

  Future<bool> requestNotifications() async => await android?.requestNotificationsPermission() ?? false;

  Future<bool> requestExactAlarms() async => await android?.requestExactAlarmsPermission() ?? false;

  Future<void> openNotificationSettings() async => android?.openAppNotificationSettings();

  @override
  Future<bool> canScheduleExact() async {
    try {
      return await android?.canScheduleExactNotifications() ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> schedule(PlannedNotification n, {required bool exact}) async {
    await initTimezone();
    final when = tz.TZDateTime(tz.local, n.fireAt.year, n.fireAt.month, n.fireAt.day, n.fireAt.hour, n.fireAt.minute);
    final summary = n.kind == PlannedKind.resumo || n.kind == PlannedKind.backup;
    final details = AndroidNotificationDetails(
      summary ? channelSummary : channelReminders,
      summary ? 'Resumo diário' : 'Lembretes',
      importance: summary ? Importance.defaultImportance : Importance.high,
      priority: summary ? Priority.defaultPriority : Priority.high,
      silent: summary,
      category: summary ? AndroidNotificationCategory.event : AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(n.body, contentTitle: n.title),
      color: const Color(0xFF8FA8FF),
      icon: '@drawable/ic_notificacao',
      actions: n.isTaskReminder
          ? const [
              AndroidNotificationAction(actionComplete, 'Concluir', cancelNotification: true),
              AndroidNotificationAction(actionSnooze, 'Adiar 1h', cancelNotification: true),
            ]
          : null,
    );
    await plugin.zonedSchedule(
      id: n.id,
      scheduledDate: when,
      notificationDetails: NotificationDetails(android: details),
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      title: n.title,
      body: n.body,
      payload: n.payload,
    );
  }

  /// Mostra na hora (confirmação de ação em segundo plano).
  Future<void> showNow(int id, String title, String body, {String? payload}) => plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(channelSummary, 'Resumo diário',
              silent: true, icon: '@drawable/ic_notificacao', timeoutAfter: 8000),
        ),
      );

  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => plugin.cancelAllPendingNotifications();
}

/// Gateway que não faz nada (testes de widget e plataformas sem plugin).
class NoopNotificationGateway implements NotificationGateway {
  const NoopNotificationGateway();
  @override
  Future<bool> canScheduleExact() async => true;
  @override
  Future<void> schedule(PlannedNotification n, {required bool exact}) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}
