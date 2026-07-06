package com.h1ghsyst3m.ytnd

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannelName = "ytnd/share_intent"
    private val eventChannelName = "ytnd/share_intent_events"

    private var initialSharedText: String? = null
    private val pendingSharedTexts = mutableListOf<String>()
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent, isInitial = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialSharedText" -> {
                result.success(initialSharedText)
                initialSharedText = null
            }
            else -> result.notImplemented()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, isInitial = false)
    }

    private fun handleIntent(intent: Intent?, isInitial: Boolean) {
        val sharedText = extractSharedText(intent)?.trim()
        if (sharedText.isNullOrEmpty()) return

        if (isInitial) {
            initialSharedText = sharedText
            return
        }

        if (eventSink != null) {
            eventSink?.success(sharedText)
        } else {
            pendingSharedTexts.add(sharedText)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        val parts = mutableListOf<String>()

        when (intent.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> {
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let { parts.add(it) }
                intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.let { parts.add(it) }
                intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString()?.let { parts.add(it) }
                addClipText(intent.clipData, parts)
            }
            Intent.ACTION_VIEW -> intent.dataString?.let { parts.add(it) }
        }

        return parts
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString("\n")
            .ifEmpty { null }
    }

    private fun addClipText(clipData: ClipData?, parts: MutableList<String>) {
        if (clipData == null) return
        for (index in 0 until clipData.itemCount) {
            val item = clipData.getItemAt(index)
            item.text?.toString()?.let { parts.add(it) }
            item.uri?.toString()?.let { parts.add(it) }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        pendingSharedTexts.forEach { events?.success(it) }
        pendingSharedTexts.clear()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
