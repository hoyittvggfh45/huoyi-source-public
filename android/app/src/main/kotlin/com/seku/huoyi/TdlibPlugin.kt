package com.seku.huoyi

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
import org.drinkless.tdlib.TdApi
import java.util.concurrent.Executors

object TdlibPlugin {

    private const val METHOD_CHANNEL = "huoyi/tdlib"
    private const val AUTH_CHANNEL = "huoyi/tdlib/auth"
    private const val FILE_CHANNEL = "huoyi/tdlib/file"

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var context: Context? = null
    private var client: TdlibClient? = null
    private var auth: TdlibAuthRepository? = null
    private var scope: CoroutineScope? = null
    private var authSink: EventChannel.EventSink? = null
    private var fileSink: EventChannel.EventSink? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        this.context = context.applicationContext
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> runAsync(result) { init(call.argument<Int>("apiId") ?: 0, call.argument<String>("apiHash").orEmpty(), call.argument<String>("databaseDir").orEmpty(), call.argument<String>("filesDir").orEmpty()) }
                "authState" -> runAsync(result) { mapOf("state" to stateMap(auth?.state?.value)) }
                "requestQr" -> runAsync(result) { auth?.requestQr(); mapOf("ok" to true) }
                "requestPhone" -> runAsync(result) { auth?.requestPhone(call.argument<String>("phone").orEmpty()); mapOf("ok" to true) }
                "submitCode" -> runAsync(result) { auth?.submitCode(call.argument<String>("code").orEmpty()); mapOf("ok" to true) }
                "submitPassword" -> runAsync(result) { auth?.checkPassword(call.argument<String>("password").orEmpty()); mapOf("ok" to true) }
                "restartQr" -> runAsync(result) { auth?.restartLogin(); mapOf("ok" to true) }
                "logout" -> runAsync(result) { logout(); mapOf("ok" to true) }
                "getMe" -> runAsync(result) { getMe() }
                "chats" -> runAsync(result) { chats(call.argument<Int>("limit") ?: 40) }
                "chatHistory" -> runAsync(result) { chatHistory(call.argument<Long>("chatId") ?: 0L, call.argument<Long>("fromMessageId") ?: 0L, call.argument<Int>("limit") ?: 30) }
                "searchMessages" -> runAsync(result) { searchMessages(call.argument<String>("query").orEmpty(), call.argument<Int>("limit") ?: 50) }
                "searchChatMessages" -> runAsync(result) { searchChatMessages(call.argument<Long>("chatId") ?: 0L, call.argument<String>("query").orEmpty(), call.argument<Long>("fromMessageId") ?: 0L, call.argument<Int>("limit") ?: 30) }
                "downloadFile" -> runAsync(result) { downloadFile(call.argument<Int>("fileId") ?: 0, call.argument<Int>("priority") ?: 32) }
                "getFile" -> runAsync(result) { getFile(call.argument<Int>("fileId") ?: 0) }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, AUTH_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                authSink = events
                pushAuthState()
            }

            override fun onCancel(arguments: Any?) {
                authSink = null
            }
        })
        EventChannel(messenger, FILE_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                fileSink = events
            }

            override fun onCancel(arguments: Any?) {
                fileSink = null
            }
        })
    }

    private fun runAsync(result: MethodChannel.Result, block: suspend () -> Map<String, Any?>) {
        executor.execute {
            try {
                val value = kotlinx.coroutines.runBlocking { block() }
                mainHandler.post { result.success(value) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("tdlib_error", e.message ?: "TDLib call failed", null) }
            }
        }
    }

    private fun ensureScope(): CoroutineScope {
        val existing = scope
        if (existing != null) return existing
        val created = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = created
        return created
    }

    private fun init(apiId: Int, apiHash: String, databaseDir: String, filesDir: String): Map<String, Any?> {
        if (apiId == 0 || apiHash.isEmpty() || databaseDir.isEmpty() || filesDir.isEmpty()) {
            throw IllegalStateException("缺少 Telegram API 凭证或数据库目录")
        }
        val current = auth
        if (current != null && client != null) {
            return mapOf("state" to stateMap(current.state.value))
        }
        val newScope = ensureScope()
        val newClient = TdlibClient()
        if (!newClient.ready) {
            throw IllegalStateException("TDLib 原生库加载失败，当前设备不支持 TDLib 登录")
        }
        val newAuth = TdlibAuthRepository(
            client = newClient,
            apiId = apiId,
            apiHash = apiHash,
            databaseDir = databaseDir,
            filesDir = filesDir,
            scope = newScope,
        )
        client = newClient
        auth = newAuth
        newScope.launch {
            newAuth.state.collect { state ->
                pushAuthState()
                if (state is TdlibAuthState.LoggedOut) {
                    teardown()
                }
            }
        }
        newScope.launch {
            newAuth.connected.collect { connected ->
                postAuthEvent(mapOf("connected" to connected))
            }
        }
        newScope.launch {
            newClient.updates.filterIsInstance<TdApi.UpdateFile>().collect { update ->
                postFileEvent(fileMap(update.file))
            }
        }
        newAuth.start()
        return mapOf("state" to stateMap(newAuth.state.value))
    }

    private fun teardown() {
        val oldScope = scope
        scope = null
        client = null
        auth = null
        oldScope?.cancel()
    }

    private fun logout(): Map<String, Any?> {
        val repo = auth
        if (repo == null) {
            teardown()
            return mapOf("ok" to true)
        }
        repo.logOut { }
        return mapOf("ok" to true)
    }

    private fun requireClient(): TdlibClient {
        return client ?: throw IllegalStateException("TDLib 未初始化，请先登录")
    }

    private suspend fun getMe(): Map<String, Any?> {
        val user = requireClient().send<TdApi.User>(TdApi.GetMe())
        return mapOf(
            "id" to user.id,
            "firstName" to (user.firstName ?: ""),
            "lastName" to (user.lastName ?: ""),
            "username" to (user.usernames?.activeUsernames?.firstOrNull() ?: ""),
        )
    }

    private suspend fun chats(limit: Int): Map<String, Any?> {
        val c = requireClient()
        runCatching { c.send<TdApi.Ok>(TdApi.LoadChats(TdApi.ChatListMain(), limit)) }
            .onFailure { if (it !is TdlibException || it.error.code != 404) throw it }
        val found = c.send<TdApi.Chats>(TdApi.GetChats(TdApi.ChatListMain(), limit))
        val items = mutableListOf<Map<String, Any?>>()
        for (chatId in found.chatIds) {
            val chat = runCatching { c.send<TdApi.Chat>(TdApi.GetChat(chatId)) }.getOrNull() ?: continue
            items.add(chatMap(chat))
        }
        return mapOf("chats" to items)
    }

    private suspend fun chatHistory(chatId: Long, fromMessageId: Long, limit: Int): Map<String, Any?> {
        val c = requireClient()
        val found = c.send<TdApi.FoundChatMessages>(
            TdApi.SearchChatMessages(
                chatId, null, "", null, fromMessageId, 0, limit,
                TdApi.SearchMessagesFilterPhotoAndVideo()
            )
        )
        return mapOf(
            "messages" to found.messages.mapNotNull { messageMap(it) },
            "nextFromMessageId" to found.nextFromMessageId,
        )
    }

    private suspend fun searchMessages(query: String, limit: Int): Map<String, Any?> {
        val c = requireClient()
        val found = c.send<TdApi.FoundMessages>(
            TdApi.SearchMessages(
                TdApi.ChatListMain(), query, "", limit,
                TdApi.SearchMessagesFilterVideo(), null, 0, 0
            )
        )
        return mapOf(
            "messages" to found.messages.mapNotNull { messageMap(it) },
            "nextOffset" to (found.nextOffset ?: ""),
            "totalCount" to found.totalCount,
        )
    }

    private suspend fun searchChatMessages(chatId: Long, query: String, fromMessageId: Long, limit: Int): Map<String, Any?> {
        val c = requireClient()
        val found = c.send<TdApi.FoundChatMessages>(
            TdApi.SearchChatMessages(
                chatId, null, query, null, fromMessageId, 0, limit,
                TdApi.SearchMessagesFilterVideo()
            )
        )
        return mapOf(
            "messages" to found.messages.mapNotNull { messageMap(it) },
            "nextFromMessageId" to found.nextFromMessageId,
        )
    }

    private suspend fun downloadFile(fileId: Int, priority: Int): Map<String, Any?> {
        val c = requireClient()
        val file = c.send<TdApi.File>(TdApi.DownloadFile(fileId, priority, 0, 0, false))
        return fileMap(file)
    }

    private suspend fun getFile(fileId: Int): Map<String, Any?> {
        val c = requireClient()
        val cached = c.latestFile(fileId)
        if (cached != null) return fileMap(cached)
        return fileMap(c.send<TdApi.File>(TdApi.GetFile(fileId)))
    }

    private fun chatMap(chat: TdApi.Chat): Map<String, Any?> {
        val type = when (val t = chat.type) {
            is TdApi.ChatTypeSupergroup -> if (t.isChannel) "channel" else "supergroup"
            is TdApi.ChatTypeBasicGroup -> "group"
            is TdApi.ChatTypePrivate -> "private"
            is TdApi.ChatTypeSecret -> "secret"
            else -> "unknown"
        }
        return mapOf(
            "id" to chat.id,
            "title" to chat.title,
            "type" to type,
            "isProtected" to chat.hasProtectedContent,
        )
    }

    private fun messageMap(message: TdApi.Message): Map<String, Any?>? {
        val content = message.content
        if (content !is TdApi.MessageVideo) return null
        val video = content.video
        val file = video.video
        val thumb = video.thumbnail
        return mapOf(
            "messageId" to message.id,
            "chatId" to message.chatId,
            "date" to message.date,
            "type" to "video",
            "duration" to video.duration,
            "width" to video.width,
            "height" to video.height,
            "fileName" to video.fileName,
            "mimeType" to video.mimeType,
            "supportsStreaming" to video.supportsStreaming,
            "fileId" to file.id,
            "fileSize" to if (file.size > 0) file.size else file.expectedSize,
            "thumbFileId" to (thumb?.file?.id ?: 0),
            "thumbWidth" to (thumb?.width ?: 0),
            "thumbHeight" to (thumb?.height ?: 0),
            "caption" to (content.caption?.text?.trim().orEmpty()),
        )
    }

    private fun fileMap(file: TdApi.File): Map<String, Any?> {
        val local = file.local
        return mapOf(
            "id" to file.id,
            "size" to file.size,
            "expectedSize" to file.expectedSize,
            "localPath" to (local?.path ?: ""),
            "downloadedPrefixSize" to (local?.downloadedPrefixSize ?: 0),
            "downloadOffset" to (local?.downloadOffset ?: 0),
            "isDownloadingCompleted" to (local?.isDownloadingCompleted ?: false),
            "isDownloadingActive" to (local?.isDownloadingActive ?: false),
        )
    }

    private fun stateMap(state: TdlibAuthState?): Map<String, Any?> {
        return when (state) {
            null -> mapOf("name" to "initializing")
            is TdlibAuthState.Initializing -> mapOf("name" to "initializing")
            is TdlibAuthState.WaitPhoneNumber -> mapOf("name" to "waitPhoneNumber")
            is TdlibAuthState.ShowQr -> mapOf("name" to "showQr", "link" to state.link)
            is TdlibAuthState.WaitCode -> mapOf(
                "name" to "waitCode",
                "phone" to state.phone,
                "error" to (state.error ?: ""),
                "checking" to state.checking,
            )
            is TdlibAuthState.WaitPassword -> mapOf(
                "name" to "waitPassword",
                "hint" to (state.hint ?: ""),
                "error" to (state.error ?: ""),
                "checking" to state.checking,
            )
            is TdlibAuthState.Ready -> mapOf("name" to "ready")
            is TdlibAuthState.Error -> mapOf("name" to "error", "message" to state.message)
            is TdlibAuthState.SigningOut -> mapOf("name" to "signingOut")
            is TdlibAuthState.LoggedOut -> mapOf("name" to "loggedOut")
        }
    }

    private fun pushAuthState() {
        val state = auth?.state?.value
        postAuthEvent(mapOf("state" to stateMap(state)))
    }

    private fun postAuthEvent(event: Map<String, Any?>) {
        val sink = authSink ?: return
        mainHandler.post { runCatching { sink.success(event) } }
    }

    private fun postFileEvent(event: Map<String, Any?>) {
        val sink = fileSink ?: return
        mainHandler.post { runCatching { sink.success(event) } }
    }
}
