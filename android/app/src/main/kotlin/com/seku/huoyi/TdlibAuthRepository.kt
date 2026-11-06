package com.seku.huoyi

import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
import org.drinkless.tdlib.TdApi
import java.io.File

sealed interface TdlibAuthState {
    data object Initializing : TdlibAuthState
    data object WaitPhoneNumber : TdlibAuthState
    data class ShowQr(val link: String) : TdlibAuthState
    data class WaitCode(
        val phone: String = "",
        val error: String? = null,
        val checking: Boolean = false,
    ) : TdlibAuthState
    data class WaitPassword(
        val hint: String? = null,
        val error: String? = null,
        val checking: Boolean = false,
    ) : TdlibAuthState
    data object Ready : TdlibAuthState
    data class Error(val message: String) : TdlibAuthState
    data object SigningOut : TdlibAuthState
    data object LoggedOut : TdlibAuthState
}

class TdlibAuthRepository(
    private val client: TdlibClient,
    private val apiId: Int,
    private val apiHash: String,
    private val databaseDir: String,
    private val filesDir: String,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<TdlibAuthState>(TdlibAuthState.Initializing)
    val state: StateFlow<TdlibAuthState> = _state.asStateFlow()

    private val _connected = MutableStateFlow(true)
    val connected: StateFlow<Boolean> = _connected.asStateFlow()
    private var disconnectJob: Job? = null

    private var parametersSent = false
    private var qrRequested = false
    private var currentPhone = ""

    fun start() {
        scope.launch {
            client.updates
                .filterIsInstance<TdApi.UpdateAuthorizationState>()
                .collect { handle(it.authorizationState) }
        }
        scope.launch {
            client.updates
                .filterIsInstance<TdApi.UpdateConnectionState>()
                .collect { handleConnection(it.state) }
        }
        scope.launch {
            runCatching { client.send<TdApi.AuthorizationState>(TdApi.GetAuthorizationState()) }
                .onSuccess { handle(it) }
                .onFailure { _state.value = TdlibAuthState.Error(it.message ?: "Failed to query auth state") }
        }
    }

    private fun handleConnection(state: TdApi.ConnectionState) {
        val live = state is TdApi.ConnectionStateReady || state is TdApi.ConnectionStateUpdating
        if (live) {
            disconnectJob?.cancel()
            disconnectJob = null
            _connected.value = true
        } else if (_connected.value && disconnectJob == null) {
            disconnectJob = scope.launch {
                delay(DISCONNECT_DEBOUNCE_MS)
                _connected.value = false
                disconnectJob = null
            }
        }
    }

    private suspend fun handle(authState: TdApi.AuthorizationState) {
        if (authState !is TdApi.AuthorizationStateWaitPhoneNumber) qrRequested = false
        when (authState) {
            is TdApi.AuthorizationStateWaitTdlibParameters -> setParameters()
            is TdApi.AuthorizationStateWaitPhoneNumber ->
                _state.value = TdlibAuthState.WaitPhoneNumber
            is TdApi.AuthorizationStateWaitOtherDeviceConfirmation ->
                _state.value = TdlibAuthState.ShowQr(authState.link)
            is TdApi.AuthorizationStateWaitCode ->
                _state.value = TdlibAuthState.WaitCode(phone = currentPhone)
            is TdApi.AuthorizationStateWaitPassword ->
                _state.value = TdlibAuthState.WaitPassword(
                    hint = authState.passwordHint.takeIf { it.isNotBlank() }
                )
            is TdApi.AuthorizationStateReady -> _state.value = TdlibAuthState.Ready
            is TdApi.AuthorizationStateLoggingOut -> _state.value = TdlibAuthState.SigningOut
            is TdApi.AuthorizationStateClosed -> _state.value = TdlibAuthState.LoggedOut
            else -> Unit
        }
    }

    fun logOut(onError: (String) -> Unit) {
        scope.launch {
            runCatching { client.send<TdApi.Ok>(TdApi.LogOut()) }
                .onFailure { e -> onError(e.message ?: "Sign-out failed") }
        }
    }

    fun requestQr() {
        if (qrRequested) return
        qrRequested = true
        scope.launch {
            runCatching { client.send<TdApi.Ok>(TdApi.RequestQrCodeAuthentication(LongArray(0))) }
                .onFailure { e ->
                    qrRequested = false
                    _state.value = TdlibAuthState.Error(e.message ?: "requestQrCodeAuthentication failed")
                }
        }
    }

    fun requestPhone(phone: String) {
        val normalized = phone.trim()
        if (normalized.isEmpty()) {
            _state.value = TdlibAuthState.Error("手机号不能为空")
            return
        }
        currentPhone = normalized
        scope.launch {
            runCatching {
                client.send<TdApi.Ok>(
                    TdApi.SetAuthenticationPhoneNumber(normalized, null)
                )
            }.onFailure { e ->
                _state.value = TdlibAuthState.Error(e.message ?: "setAuthenticationPhoneNumber failed")
            }
        }
    }

    fun submitCode(code: String) {
        val current = _state.value as? TdlibAuthState.WaitCode ?: return
        if (current.checking) return
        _state.value = current.copy(error = null, checking = true)
        scope.launch {
            runCatching { client.send<TdApi.Ok>(TdApi.CheckAuthenticationCode(code.trim())) }
                .onFailure { e ->
                    val s = _state.value
                    if (s is TdlibAuthState.WaitCode) {
                        _state.value = s.copy(error = e.message ?: "验证码错误", checking = false)
                    }
                }
        }
    }

    fun checkPassword(password: String) {
        val current = _state.value as? TdlibAuthState.WaitPassword ?: return
        if (current.checking) return
        _state.value = current.copy(error = null, checking = true)
        scope.launch {
            runCatching { client.send<TdApi.Ok>(TdApi.CheckAuthenticationPassword(password)) }
                .onFailure { e ->
                    val wrongPassword = e is TdlibException && e.error.message == "PASSWORD_HASH_INVALID"
                    val message = if (wrongPassword) {
                        "二步验证密码错误"
                    } else {
                        e.message ?: "二步验证密码错误"
                    }
                    val s = _state.value
                    if (s is TdlibAuthState.WaitPassword) {
                        _state.value = s.copy(error = message, checking = false)
                    }
                }
        }
    }

    fun restartLogin() {
        val current = _state.value as? TdlibAuthState.WaitPassword ?: return
        if (current.checking) return
        scope.launch {
            runCatching { client.send<TdApi.Ok>(TdApi.RequestQrCodeAuthentication(LongArray(0))) }
                .onFailure { e ->
                    val s = _state.value
                    if (s is TdlibAuthState.WaitPassword) {
                        _state.value = s.copy(error = e.message, checking = false)
                    }
                }
        }
    }

    private suspend fun setParameters() {
        if (parametersSent) return
        if (apiId == 0 || apiHash.isBlank()) {
            _state.value = TdlibAuthState.Error(
                "Missing Telegram credentials. Set TG_API_ID and TG_API_HASH."
            )
            return
        }
        parametersSent = true
        val params = TdApi.SetTdlibParameters().apply {
            useTestDc = false
            databaseDirectory = databaseDir
            filesDirectory = filesDir
            useFileDatabase = true
            useChatInfoDatabase = true
            useMessageDatabase = true
            useSecretChats = false
            apiId = this@TdlibAuthRepository.apiId
            apiHash = this@TdlibAuthRepository.apiHash
            systemLanguageCode = "zh"
            deviceModel = Build.MODEL ?: "Android"
            systemVersion = Build.VERSION.RELEASE ?: "Android"
            applicationVersion = BuildConfig.VERSION_NAME
        }
        runCatching { client.send<TdApi.Ok>(params) }
            .onFailure { _state.value = TdlibAuthState.Error(it.message ?: "setTdlibParameters failed") }
    }

    private companion object {
        const val DISCONNECT_DEBOUNCE_MS = 2500L
    }
}
