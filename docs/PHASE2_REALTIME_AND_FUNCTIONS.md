# Phase 2 — Edge Functions + Realtime Live Sync

This document shows exactly how to use the Phase 2 backend implementation.

## 1) Deploy SQL migration

Run in Supabase SQL Editor (or `supabase db push` after linking project):

- `supabase/migrations/20260425_phase2_appointments_queue_notifications.sql`

This migration adds:
- Queue auto-position and resequencing triggers
- DB constraints to prevent double-booking
- Status transition guardrails
- Realtime publication for `app.appointments`
- Notification history table + audit trigger + appointment notification trigger

## 2) Deploy Edge Functions

Functions included:
- `book`
- `accept`
- `decline`
- `update`
- `complete`
- `cancel`

Deploy commands:

```bash
npx supabase functions deploy book
npx supabase functions deploy accept
npx supabase functions deploy decline
npx supabase functions deploy update
npx supabase functions deploy complete
npx supabase functions deploy cancel
```

**Critical security:**
- `SUPABASE_SERVICE_ROLE_KEY` is used only in Edge Function environment.
- Never place service role key in Flutter app.

## 3) Realtime subscription snippet (Flutter)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> initSupabaseRealtime({
  required String proxyUrl,
  required String anonKey,
}) async {
  await Supabase.initialize(
    url: proxyUrl,
    anonKey: anonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.info,
    ),
  );
}

RealtimeChannel subscribeAppointmentStatus({
  required String appointmentId,
  required void Function(Map<String, dynamic> newRow) onChanged,
}) {
  final client = Supabase.instance.client;

  final channel = client.channel('appointment-status-$appointmentId');

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'app',
        table: 'appointments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: appointmentId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          final status = (row['status'] ?? '').toString();

          // Live sync states requested for phase-2.
          if (status == 'pending' ||
              status == 'confirmed' ||
              status == 'delayed' ||
              status == 'completed') {
            onChanged(row);
          }
        },
      )
      .subscribe();

  return channel;
}

Future<void> disposeAppointmentChannel(RealtimeChannel channel) async {
  await Supabase.instance.client.removeChannel(channel);
}
```

## 4) Calling Edge Functions safely

Client call pattern:
- Endpoint: `https://<your-supabase-or-proxy>/functions/v1/<function-name>`
- Header: `Authorization: Bearer <user-access-token>`
- Body: JSON payload

**Zero client-side key exposure rule:**
- Client must never contain service role key.
- Service role key exists only in Supabase Edge Function secrets.
