package com.duowallet.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class DuoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val hideAmounts = prefs.getString("hide_amounts", "false") == "true"
        val remaining = if (hideAmounts) "•••• Ft" else (prefs.getString("remaining_budget", "0 Ft") ?: "0 Ft")
        val myTotal = if (hideAmounts) "•••• Ft" else (prefs.getString("my_total_month", "0 Ft") ?: "0 Ft")

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.duo_widget)
            views.setTextViewText(R.id.widget_remaining_budget, "Budget left: $remaining")
            views.setTextViewText(R.id.widget_my_total, "My Total: $myTotal")

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = Uri.parse("duowallet://quick-add")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_quick_add_btn, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
