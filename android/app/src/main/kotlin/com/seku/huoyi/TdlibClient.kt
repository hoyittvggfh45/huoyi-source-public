package com.seku.huoyi

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi
import java.util.concurrent.ConcurrentHashMap

class TdlibException(val error: TdApi.Error) :
    Exception("TDLib error ${error.code}: ${error.message}")

class TdlibClient {

    private val nativeReady: Boolean = NativeLibs.ensureLoaded()

    private val _updates = MutableSharedFlow<TdApi.Update>(
        extraBufferCapacity = 512,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val updates: SharedFlow<TdApi.Update> = _updates.asSharedFlow()

    private val fileCache = ConcurrentHashMap<Int, TdApi.File>()

    private val client: Client = Client.create(
        { obj -> onIncoming(obj) },
        { e -> e.printStackTrace() },
        { e -> e.printStackTrace() }
    )

    init {
        Client.execute(TdApi.SetLogVerbosityLevel(1))
    }

    private fun onIncoming(obj: TdApi.Object) {
        if (obj is TdApi.Update) {
            if (obj is TdApi.UpdateFile) fileCache[obj.file.id] = obj.file
            _updates.tryEmit(obj)
        }
    }

    fun latestFile(fileId: Int): TdApi.File? = fileCache[fileId]

    @Suppress("UNCHECKED_CAST")
    suspend fun <T : TdApi.Object> send(function: TdApi.Function<*>): T {
        val deferred = CompletableDeferred<TdApi.Object>()
        client.send(function) { result -> deferred.complete(result) }
        val result = deferred.await()
        if (result is TdApi.Error) throw TdlibException(result)
        if (result is TdApi.File) fileCache[result.id] = result
        return result as T
    }

    suspend fun awaitFileUpdate(fileId: Int, timeoutMs: Long): TdApi.File? =
        withTimeoutOrNull(timeoutMs) {
            updates.filterIsInstance<TdApi.UpdateFile>().first { it.file.id == fileId }.file
        }

    fun close() {
        client.send(TdApi.Close()) { }
    }
}

private object NativeLibs {
    @Volatile
    private var loaded = false

    @Synchronized
    fun ensureLoaded(): Boolean {
        if (!loaded) {
            System.loadLibrary("cryptox")
            System.loadLibrary("sslx")
            System.loadLibrary("tdjni")
            loaded = true
        }
        return true
    }
}
