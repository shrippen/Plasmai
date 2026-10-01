package com.github.shrippen.plasmai;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

/**
 * The permanent notification while a timer runs (app/platform/trackingnotice_android.cpp):
 * ongoing, with a chronometer from the entry's begin; a tap opens the app.
 */
public final class TrackingNotice {
    private static final String CHANNEL = "tracking";
    private static final int ID = 1;
    private static final int PERMISSION_REQUEST = 7301;
    private static boolean permissionAsked = false;

    private TrackingNotice() {
    }

    public static void show(Context context, String title, String text, long sinceMsecs) {
        if (!canPost(context)) {
            return;
        }

        NotificationManager manager = context.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL,
                context.getString(R.string.tracking_channel), NotificationManager.IMPORTANCE_LOW);
        manager.createNotificationChannel(channel);

        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent tap = PendingIntent.getActivity(context, 0, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_tracking)
                .setContentTitle(title)
                .setContentText(text)
                .setWhen(sinceMsecs)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
                .setContentIntent(tap);
        NotificationManagerCompat.from(context).notify(ID, builder.build());
    }

    public static void hide(Context context) {
        NotificationManagerCompat.from(context).cancel(ID);
    }

    // Android 13+ asks for the permission once per start of the app; QML shows the
    // notification again when the app is back in front (after the dialog).
    private static boolean canPost(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true;
        }
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return true;
        }
        if (!permissionAsked && context instanceof Activity) {
            permissionAsked = true;
            ((Activity) context).requestPermissions(
                    new String[] { Manifest.permission.POST_NOTIFICATIONS }, PERMISSION_REQUEST);
        }
        return false;
    }
}
