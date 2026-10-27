package com.seku.huoyi

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.github.catvod.spider.Init
import dalvik.system.DexClassLoader
import dalvik.system.DexFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.lang.reflect.InvocationTargetException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object JarBridge {

    private const val CHANNEL = "duanju/jarbridge"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val loaders = ConcurrentHashMap<String, DexClassLoader>()
    private val spiders = ConcurrentHashMap<String, Any>()
    private val initialized = ConcurrentHashMap.newKeySet<String>()

    fun register(messenger: BinaryMessenger, context: Context) {
        Init.init(context)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureJar" -> {
                    val configId = call.argument<String>("configId").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    val md5 = call.argument<String>("md5").orEmpty()
                    if (configId.isEmpty() || url.isEmpty()) {
                        result.error("jar_invalid", "缺少 jar 配置标识或下载地址", null)
                    } else {
                        runAsync(result) { ensureJar(context, configId, url, md5) }
                    }
                }
                "call" -> {
                    val siteId = call.argument<String>("siteId").orEmpty()
                    val jarPath = call.argument<String>("jarPath").orEmpty()
                    val className = call.argument<String>("className").orEmpty()
                    val method = call.argument<String>("method").orEmpty()
                    if (siteId.isEmpty() || jarPath.isEmpty() || className.isEmpty() || method.isEmpty()) {
                        result.error("jar_invalid", "缺少 jar 站点调用参数", null)
                    } else {
                        val args = call.argument<Map<String, Any?>>("args") ?: emptyMap()
                        val ext = call.argument<String>("ext").orEmpty()
                        val configId = call.argument<String>("configId").orEmpty()
                        runAsync(result) {
                            mapOf("text" to callSpider(context, siteId, configId, jarPath, className, ext, method, args))
                        }
                    }
                }
                "release" -> {
                    val siteId = call.argument<String>("siteId").orEmpty()
                    runAsync(result) {
                        releaseSpider(siteId)
                        mapOf("released" to true)
                    }
                }
                "enumerate" -> {
                    val jarPath = call.argument<String>("jarPath").orEmpty()
                    if (jarPath.isEmpty()) {
                        result.error("jar_invalid", "缺少待枚举的 jar 路径", null)
                    } else {
                        runAsync(result) { enumerateClasses(context, jarPath) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Map<String, Any?>) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                val message = error.message ?: error.javaClass.simpleName
                mainHandler.post { result.error("jar_error", message, null) }
            }
        }
    }

    private fun jarFile(context: Context, configId: String): File {
        val dir = File(context.filesDir, "jarbridge")
        if (!dir.exists()) dir.mkdirs()
        val safe = configId.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return File(dir, "$safe.jar")
    }

    private fun md5Of(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun ensureJar(context: Context, configId: String, url: String, expectedMd5: String): Map<String, Any?> {
        val target = jarFile(context, configId)
        val expected = expectedMd5.trim().lowercase()
        if (target.exists()) {
            val current = md5Of(target)
            if (expected.isEmpty() || current == expected) {
                JarFilePrep.sealForLoad(target)
                return mapOf("path" to target.absolutePath, "md5" to current)
            }
        }
        val temp = File(target.parentFile, target.name + ".part")
        if (temp.exists() && !temp.delete()) JarFilePrep.makeWritable(temp)
        if (url.startsWith("http://") || url.startsWith("https://")) {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 20000
            connection.readTimeout = 60000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "okhttp/4.12.0")
            try {
                val code = connection.responseCode
                if (code !in 200..299) throw IllegalStateException("jar 下载失败：HTTP $code（$url）")
                connection.inputStream.use { input ->
                    FileOutputStream(temp).use { output -> input.copyTo(output) }
                }
            } finally {
                connection.disconnect()
            }
        } else {
            val source = File(url.removePrefix("file://"))
            if (!source.exists()) throw IllegalStateException("本地 jar 文件不存在：$url")
            source.inputStream().use { input ->
                FileOutputStream(temp).use { output -> input.copyTo(output) }
            }
        }
        val actual = md5Of(temp)
        if (expected.isNotEmpty() && actual != expected) {
            temp.delete()
            throw IllegalStateException("jar MD5 校验不符：配置要求 $expected，实际 $actual，已拒绝加载")
        }
        JarFilePrep.replaceTarget(temp, target)
        loaders.remove(configId)
        val stale = spiders.keys.filter { it.startsWith("jar:$configId:") }
        stale.forEach { releaseSpider(it) }
        return mapOf("path" to target.absolutePath, "md5" to actual)
    }

    @Suppress("DEPRECATION")
    private fun enumerateClasses(context: Context, jarPath: String): Map<String, Any?> {
        val file = File(jarPath)
        if (!file.exists()) throw IllegalStateException("jar 文件不存在：$jarPath")
        JarFilePrep.sealForLoad(file)
        val optimized = File(context.codeCacheDir, "jarbridge_enum")
        if (!optimized.exists()) optimized.mkdirs()
        val dexFile = DexFile.loadDex(
            jarPath,
            File(optimized, file.name + ".odex").absolutePath,
            0
        )
        val names = mutableListOf<String>()
        try {
            val entries = dexFile.entries()
            while (entries.hasMoreElements()) {
                val name = entries.nextElement()
                if (name.startsWith("com.github.catvod.spider.") && !name.contains('$')) {
                    names.add(name)
                }
            }
        } finally {
            dexFile.close()
        }
        val loader = DexClassLoader(jarPath, optimized.absolutePath, null, context.classLoader)
        val classes = names.sorted().map { name ->
            var instantiable = false
            var reason = ""
            try {
                val type = loader.loadClass(name)
                when {
                    type.isInterface -> reason = "接口，不可实例化"
                    java.lang.reflect.Modifier.isAbstract(type.modifiers) ->
                        reason = "抽象类，不可实例化"
                    !com.github.catvod.crawler.Spider::class.java.isAssignableFrom(type) ->
                        reason = "未继承 catvod Spider 基类"
                    else -> {
                        type.getConstructor()
                        instantiable = true
                    }
                }
            } catch (error: NoSuchMethodException) {
                reason = "缺少公开无参构造方法"
            } catch (error: Throwable) {
                reason = "类加载失败：${error.message ?: error.javaClass.simpleName}"
            }
            mapOf("className" to name, "instantiable" to instantiable, "reason" to reason)
        }
        return mapOf("classes" to classes)
    }

    private fun loaderFor(context: Context, configId: String, jarPath: String): DexClassLoader {
        return loaders.computeIfAbsent(configId) {
            JarFilePrep.sealForLoad(File(jarPath))
            val optimized = File(context.codeCacheDir, "jarbridge_$configId")
            if (!optimized.exists()) optimized.mkdirs()
            DexClassLoader(jarPath, optimized.absolutePath, null, context.classLoader)
        }
    }

    private fun spiderFor(context: Context, siteId: String, configId: String, jarPath: String, className: String, ext: String): Any {
        spiders[siteId]?.let { return it }
        synchronized(spiders) {
            spiders[siteId]?.let { return it }
            val loader = loaderFor(context, configId, jarPath)
            val type = try {
                loader.loadClass(className)
            } catch (error: ClassNotFoundException) {
                throw IllegalStateException("jar 中未找到站点类 $className，该配置的 api 与 spider 不匹配或 jar 不完整")
            } catch (error: LinkageError) {
                throw IllegalStateException("jar 类 $className 加载失败（可能依赖未提供的壳组件）：${error.message}")
            }
            val instance = try {
                type.getDeclaredConstructor().newInstance()
            } catch (error: Exception) {
                throw IllegalStateException("jar 站点类 $className 无法实例化：${error.cause?.message ?: error.message}")
            }
            try {
                val init = type.getMethod("init", Context::class.java, String::class.java)
                init.invoke(instance, context.applicationContext, ext)
            } catch (error: NoSuchMethodException) {
                try {
                    type.getMethod("init", Context::class.java).invoke(instance, context.applicationContext)
                } catch (ignored: NoSuchMethodException) {
                }
            } catch (error: InvocationTargetException) {
                throw IllegalStateException("jar 站点 $className 初始化失败：${error.targetException?.message ?: error.message}")
            }
            spiders[siteId] = instance
            initialized.add(siteId)
            if (instance is com.github.catvod.crawler.Spider) {
                Init.registerSpider(className, instance)
            }
            return instance
        }
    }

    private fun releaseSpider(siteId: String) {
        val instance = spiders.remove(siteId) ?: return
        initialized.remove(siteId)
        runCatching {
            instance.javaClass.getMethod("destroy").invoke(instance)
        }
        if (instance is com.github.catvod.crawler.Spider) {
            Init.unregisterSpider(instance.javaClass.name)
        }
    }

    private fun callSpider(
        context: Context,
        siteId: String,
        configId: String,
        jarPath: String,
        className: String,
        ext: String,
        method: String,
        args: Map<String, Any?>
    ): String {
        val spider = spiderFor(context, siteId, configId, jarPath, className, ext)
        val type = spider.javaClass
        fun text(value: Any?): String = value as? String ?: ""
        return try {
            when (method) {
                "homeContent" -> text(
                    type.getMethod("homeContent", Boolean::class.javaPrimitiveType)
                        .invoke(spider, args["filter"] as? Boolean ?: true)
                )
                "homeVideoContent" -> text(type.getMethod("homeVideoContent").invoke(spider))
                "categoryContent" -> {
                    val extend = HashMap<String, String>()
                    (args["extend"] as? Map<*, *>)?.forEach { (key, value) ->
                        if (key != null && value != null) extend[key.toString()] = value.toString()
                    }
                    text(
                        type.getMethod(
                            "categoryContent",
                            String::class.java,
                            String::class.java,
                            Boolean::class.javaPrimitiveType,
                            HashMap::class.java
                        ).invoke(
                            spider,
                            args["tid"] as? String ?: "",
                            args["pg"] as? String ?: "1",
                            args["filter"] as? Boolean ?: true,
                            extend
                        )
                    )
                }
                "detailContent" -> {
                    val ids = (args["ids"] as? List<*>)?.map { it.toString() } ?: emptyList()
                    text(
                        type.getMethod("detailContent", List::class.java)
                            .invoke(spider, ids)
                    )
                }
                "searchContent" -> {
                    val key = args["key"] as? String ?: ""
                    val quick = args["quick"] as? Boolean ?: false
                    val pg = args["pg"] as? String ?: "1"
                    val paged = try {
                        type.getMethod(
                            "searchContent",
                            String::class.java,
                            Boolean::class.javaPrimitiveType,
                            String::class.java
                        )
                    } catch (ignored: NoSuchMethodException) {
                        null
                    }
                    if (paged != null) {
                        text(paged.invoke(spider, key, quick, pg))
                    } else {
                        text(
                            type.getMethod("searchContent", String::class.java, Boolean::class.javaPrimitiveType)
                                .invoke(spider, key, quick)
                        )
                    }
                }
                "playerContent" -> {
                    val vipFlags = (args["vipFlags"] as? List<*>)?.map { it.toString() } ?: emptyList<String>()
                    text(
                        type.getMethod(
                            "playerContent",
                            String::class.java,
                            String::class.java,
                            List::class.java
                        ).invoke(spider, args["flag"] as? String ?: "", args["id"] as? String ?: "", vipFlags)
                    )
                }
                else -> throw IllegalStateException("jar 桥不支持的方法：$method")
            }
        } catch (error: InvocationTargetException) {
            val cause = error.targetException
            throw IllegalStateException("jar 站点 $className.$method 执行失败：${cause?.message ?: cause?.javaClass?.simpleName ?: "未知错误"}")
        } catch (error: NoSuchMethodException) {
            throw IllegalStateException("jar 站点 $className 未实现方法 $method（与 catvod Spider 契约不符）")
        }
    }
}
