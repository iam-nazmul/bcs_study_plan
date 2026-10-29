package com.iamnazmul.bcs_study_plan

import android.Manifest
import android.app.Activity
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Writes study sessions into the Android calendar provider in bulk.
 * Each upsert call is a single applyBatch transaction, which is far faster
 * than inserting events one by one.
 */
class CalendarChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val PERMISSION_REQUEST = 4127
        private val PERMISSIONS =
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
    }

    private val channel = MethodChannel(messenger, "bcs_study_plan/calendar")
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "listCalendars" -> runAsync(result) { listCalendars() }
            "upsertEvents" -> runAsync(result) {
                upsertEvents(call.argument<Number>("calendarId")!!.toLong(), call.argument("events")!!)
            }
            "deleteEvents" -> runAsync(result) {
                deleteEvents(call.argument<List<Number>>("eventIds")!!.map { it.toLong() })
            }
            "aliveEvents" -> runAsync(result) {
                aliveEvents(call.argument<List<Number>>("eventIds")!!.map { it.toLong() })
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(grantResults: IntArray) {
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private fun hasPermission() = PERMISSIONS.all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) return result.success(true)
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(PERMISSIONS, PERMISSION_REQUEST)
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("calendar_error", e.message, null) }
            }
        }
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            Calendars._ID, Calendars.CALENDAR_DISPLAY_NAME, Calendars.ACCOUNT_NAME,
            Calendars.ACCOUNT_TYPE, Calendars.CALENDAR_COLOR,
        )
        val selection = "${Calendars.CALENDAR_ACCESS_LEVEL} >= ${Calendars.CAL_ACCESS_CONTRIBUTOR}"
        val calendars = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(Calendars.CONTENT_URI, projection, selection, null, null)?.use { c ->
            while (c.moveToNext()) {
                calendars += mapOf(
                    "id" to c.getLong(0),
                    "name" to c.getString(1),
                    "accountName" to c.getString(2),
                    "accountType" to c.getString(3),
                    "color" to c.getInt(4),
                )
            }
        }
        return calendars
    }

    /** Ids from [ids] that still exist and are not marked deleted. */
    private fun aliveEvents(ids: List<Long>): List<Long> {
        if (ids.isEmpty()) return emptyList()
        val alive = mutableListOf<Long>()
        for (chunk in ids.chunked(500)) {
            val selection = "${Events._ID} IN (${chunk.joinToString(",")}) AND ${Events.DELETED} = 0"
            activity.contentResolver.query(Events.CONTENT_URI, arrayOf(Events._ID), selection, null, null)
                ?.use { c -> while (c.moveToNext()) alive += c.getLong(0) }
        }
        return alive
    }

    /**
     * Each event map has: key, eventId (nullable), title, description, date
     * (yyyy-MM-dd), hour and reminder (minutes, 0 = none). Returns key -> eventId.
     */
    private fun upsertEvents(calendarId: Long, events: List<Map<String, Any?>>): Map<String, Long> {
        val existing = aliveEvents(events.mapNotNull { (it["eventId"] as Number?)?.toLong() }).toSet()
        val ops = ArrayList<ContentProviderOperation>()
        val inserts = mutableListOf<Pair<String, Int>>() // key -> op index of the event insert
        val ids = mutableMapOf<String, Long>()
        val zone = TimeZone.getDefault()

        for (event in events) {
            val key = event["key"] as String
            val eventId = (event["eventId"] as Number?)?.toLong()
            val reminder = (event["reminder"] as Number).toInt()
            val values = eventValues(calendarId, event, zone)

            if (eventId != null && eventId in existing) {
                ops += ContentProviderOperation
                    .newUpdate(ContentUris.withAppendedId(Events.CONTENT_URI, eventId))
                    .withValues(values).build()
                ops += ContentProviderOperation.newDelete(Reminders.CONTENT_URI)
                    .withSelection("${Reminders.EVENT_ID} = ?", arrayOf(eventId.toString())).build()
                if (reminder > 0) {
                    ops += ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValue(Reminders.EVENT_ID, eventId)
                        .withValue(Reminders.MINUTES, reminder)
                        .withValue(Reminders.METHOD, Reminders.METHOD_ALERT).build()
                }
                ids[key] = eventId
            } else {
                val index = ops.size
                ops += ContentProviderOperation.newInsert(Events.CONTENT_URI).withValues(values).build()
                if (reminder > 0) {
                    ops += ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValueBackReference(Reminders.EVENT_ID, index)
                        .withValue(Reminders.MINUTES, reminder)
                        .withValue(Reminders.METHOD, Reminders.METHOD_ALERT).build()
                }
                inserts += key to index
            }
        }

        val results = activity.contentResolver.applyBatch(Events.CONTENT_URI.authority!!, ops)
        for ((key, index) in inserts) {
            results[index].uri?.let { ids[key] = ContentUris.parseId(it) }
        }
        return ids
    }

    private fun eventValues(calendarId: Long, event: Map<String, Any?>, zone: TimeZone): ContentValues {
        val (year, month, day) = (event["date"] as String).split("-").map { it.toInt() }
        val start = Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, (event["hour"] as Number).toInt(), 0)
        }.timeInMillis
        val reminder = (event["reminder"] as Number).toInt()
        return ContentValues().apply {
            put(Events.CALENDAR_ID, calendarId)
            put(Events.TITLE, event["title"] as String)
            put(Events.DESCRIPTION, event["description"] as String)
            put(Events.DTSTART, start)
            put(Events.DTEND, start + 60 * 60 * 1000)
            put(Events.EVENT_TIMEZONE, zone.id)
            put(Events.HAS_ALARM, if (reminder > 0) 1 else 0)
        }
    }

    private fun deleteEvents(ids: List<Long>): Int {
        val ops = ArrayList(ids.map {
            ContentProviderOperation.newDelete(ContentUris.withAppendedId(Events.CONTENT_URI, it)).build()
        })
        if (ops.isEmpty()) return 0
        return activity.contentResolver.applyBatch(Events.CONTENT_URI.authority!!, ops).size
    }
}
