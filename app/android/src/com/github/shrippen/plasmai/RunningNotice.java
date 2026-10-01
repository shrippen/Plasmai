package com.github.shrippen.plasmai;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

// The notification that stays while a timer runs. Called from RunningNotice (C++).
// The system counts the time itself (chronometer), so nothing wakes the app each second.
public final class RunningNotice {
    private static final String CHANNEL_ID = "running";
    private static final int NOTICE_ID = 1;
    private static final int PERMISSION_REQUEST = 1;
    private static final int FIRST_SDK_WITH_PERMISSION = 33; // Android 13: POST_NOTIFICATIONS

    private RunningNotice() {
    }

    // title doubles as the channel's name in the system settings. startedAtMs <= 0: no chronometer.
    public static void show(Context context, String title, String body, long startedAtMs) {
        if (!mayPost(context)) {
            return;
        }

        NotificationManager manager = context.getSystemService(NotificationManager.class);
        // Low importance: no sound, no pop-up for a notice that only informs.
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, title,
                NotificationManager.IMPORTANCE_LOW);
        manager.createNotificationChannel(channel);

        Notification.Builder notice = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(icon(context))
                .setContentTitle(title)
                .setContentText(body)
                .setCategory(Notification.CATEGORY_STOPWATCH)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openApp(context));
        if (startedAtMs > 0) {
            notice.setWhen(startedAtMs).setShowWhen(true).setUsesChronometer(true);
        }
        manager.notify(NOTICE_ID, notice.build());
    }

    public static void clear(Context context) {
        context.getSystemService(NotificationManager.class).cancel(NOTICE_ID);
    }

    // Android 13+ needs the user's yes; ask once here, the app posts again after the prompt.
    private static boolean mayPost(Context context) {
        if (Build.VERSION.SDK_INT < FIRST_SDK_WITH_PERMISSION) {
            return true;
        }
        String permission = Manifest.permission.POST_NOTIFICATIONS;
        if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            return true;
        }
        if (context instanceof Activity) {
            Activity activity = (Activity) context;
            activity.runOnUiThread(() ->
                    activity.requestPermissions(new String[] {permission}, PERMISSION_REQUEST));
        }
        return false;
    }

    private static int icon(Context context) {
        return context.getResources().getIdentifier("ic_stat_timer", "drawable", context.getPackageName());
    }

    // A tap opens the running app (singleTop) instead of starting a second one.
    private static PendingIntent openApp(Context context) {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        return PendingIntent.getActivity(context, 0, launch,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
}
