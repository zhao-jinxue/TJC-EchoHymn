package com.echohymn.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import org.json.JSONObject

/**
 * EchoHymn 主 Activity。
 *
 * 额外交付 **D-2 通知权限**通道（`echohymn/permission`）：
 * Android 13+ 需运行时授予 POST_NOTIFICATIONS，否则媒体通知 importance=NONE 不显示。
 * 不引入 permission_handler —— 其 Windows 实现依赖废弃的实验性 coroutine，会破坏桌面构建。
 */
class MainActivity : FlutterActivity() {
    private val permissionChannel = "echohymn/permission"
    private val importChannel = "echohymn/import"
    private val packChannelName = "echohymn/pack"

    private var pickResult: MethodChannel.Result? = null
    private var importChannelRef: MethodChannel? = null
    private var packChannelRef: MethodChannel? = null

    // 数据包（zip）导入
    private var packPickResult: MethodChannel.Result? = null

    // 导入进度（字段便于在递归回调里累加）
    private var copiedCount = 0
    private var failedCount = 0
    private var lastNotifyAt = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                        } else {
                            val granted =
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                    PackageManager.PERMISSION_GRANTED
                            if (granted) {
                                result.success(true)
                            } else {
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    1001
                                )
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ---- 素材导入（F-4 SAF）----
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannel)
        importChannelRef = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    pickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                    }
                    startActivityForResult(intent, REQ_TREE)
                }
                "importTree" -> {
                    val uriStr = call.argument<String>("uri")
                    val targetRoot = call.argument<String>("targetRoot")
                    if (uriStr.isNullOrEmpty() || targetRoot.isNullOrEmpty()) {
                        result.error("ARG", "缺少 uri / targetRoot", null)
                    } else {
                        result.success(null) // 进度走 importProgress 回调
                        Thread { copyTree(Uri.parse(uriStr), File(targetRoot)) }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ---- 数据包（zip）导入（2026-11-13 主体 APK 方案）----
        // 用户选择 `扫描图 / 人声 / 钢琴` 压缩包 → 流式解压到 files/Hymn_Downloads，
        // **只接受**符合现有目录/文件名规则且属于该类别的文件，其余一律丢弃（不落盘）。
        val pc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, packChannelName)
        packChannelRef = pc
        pc.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickZip" -> {
                    packPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(intent, REQ_ZIP)
                }
                "importZip" -> {
                    val uriStr = call.argument<String>("uri")
                    val kind = call.argument<String>("kind") ?: ""
                    val targetRoot = call.argument<String>("targetRoot")
                    if (uriStr.isNullOrEmpty() || targetRoot.isNullOrEmpty()) {
                        result.error("ARG", "缺少 uri / targetRoot", null)
                    } else {
                        result.success(null) // 进度走 packProgress 回调
                        Thread { importZip(Uri.parse(uriStr), kind, File(targetRoot)) }.start()
                    }
                }
                "verifyInstalled" -> {
                    val targetRoot = call.argument<String>("targetRoot")
                    if (targetRoot.isNullOrEmpty()) {
                        result.error("ARG", "缺少 targetRoot", null)
                    } else {
                        Thread {
                            val report = verifyInstalled(File(targetRoot))
                            runOnUiThread { result.success(report) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_ZIP) {
            val uri = data?.data
            packPickResult?.success(
                if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null
            )
            packPickResult = null
            return
        }
        if (requestCode == REQ_TREE) {
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: SecurityException) {
                    // 部分 provider 不支持持久授权；本次导入仍可用
                }
                pickResult?.success(uri.toString())
            } else {
                pickResult?.success(null)
            }
            pickResult = null
        }
    }

    // ================= 素材复制 =================

    private fun copyTree(treeUri: Uri, targetRoot: File) {
        copiedCount = 0
        failedCount = 0
        lastNotifyAt = 0
        val root = DocumentFile.fromTreeUri(this, treeUri)
        if (root == null) {
            finishImport("无法读取所选目录")
            return
        }
        targetRoot.mkdirs()
        root.listFiles().forEach { child ->
            copyNode(child, File(targetRoot, child.name ?: "unnamed"))
        }
        finishImport(null)
    }

    private fun copyNode(node: DocumentFile, target: File) {
        if (node.isDirectory) {
            target.mkdirs()
            node.listFiles().forEach { child ->
                copyNode(child, File(target, child.name ?: "unnamed"))
            }
            return
        }
        try {
            contentResolver.openInputStream(node.uri)?.use { input ->
                target.parentFile?.mkdirs()
                target.outputStream().use { output -> input.copyTo(output) }
            }
            copiedCount++
        } catch (_: Exception) {
            failedCount++
        }
        // 每 20 个文件报一次进度（避免高频跨平台调用）
        if (copiedCount - lastNotifyAt >= 20) {
            lastNotifyAt = copiedCount
            importChannelRef?.invokeMethod(
                "importProgress",
                mapOf("copied" to copiedCount, "failed" to failedCount)
            )
        }
    }

    private fun finishImport(error: String?) {
        importChannelRef?.invokeMethod(
            "importDone",
            mapOf("copied" to copiedCount, "failed" to failedCount, "error" to error)
        )
    }

    // ================= 数据包（zip）导入 =================

    private fun importZip(uri: Uri, kind: String, root: File) {
        var accepted = 0
        var rejected = 0
        var corrupt = 0
        var failed = 0
        var processed = 0
        var manifest: Map<String, String>? = null
        var verified = false
        try {
            val input = contentResolver.openInputStream(uri)
            if (input == null) {
                packChannelRef?.invokeMethod(
                    "packDone",
                    mapOf("accepted" to 0, "rejected" to 0, "corrupt" to 0,
                        "failed" to 0, "verified" to false, "error" to "无法读取压缩包")
                )
                return
            }
            ZipInputStream(BufferedInputStream(input)).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory) {
                        val raw = entry.name.replace('\\', '/').removePrefix("./")
                        if (raw == MANIFEST_NAME) {
                            // 清单是 zip 第一个条目（打包脚本保证）→ 读完即可用于后续逐文件校验
                            val text = zip.readBytes().toString(Charsets.UTF_8)
                            manifest = parseManifest(text)
                            verified = manifest != null
                            saveManifest(root, text)
                        } else {
                            processed++
                            if (packAllowed(raw, kind)) {
                                val rel = raw.removePrefix("Hymn_Downloads/")
                                val target = File(root, "Hymn_Downloads/$rel")
                                val base = File(root, "Hymn_Downloads").canonicalPath
                                if (target.canonicalPath.startsWith(base + File.separator)) {
                                    when (writeWithCheck(zip, target, manifest?.get(raw))) {
                                        "ok" -> accepted++
                                        "corrupt" -> corrupt++
                                        else -> failed++
                                    }
                                } else {
                                    rejected++
                                }
                            } else {
                                rejected++
                            }
                            if (processed % 50 == 0) {
                                packChannelRef?.invokeMethod(
                                    "packProgress",
                                    mapOf("processed" to processed, "accepted" to accepted,
                                        "rejected" to rejected, "corrupt" to corrupt)
                                )
                            }
                        }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
        } catch (_: Exception) {
            failed++
        }
        packChannelRef?.invokeMethod(
            "packDone",
            mapOf("accepted" to accepted, "rejected" to rejected, "corrupt" to corrupt,
                "failed" to failed, "verified" to verified, "error" to null)
        )
    }

    /**
     * 路径 + 文件名白名单（2026-11-13 用户规则）：
     * 只接受 `Hymn_Downloads/<目录>/<编号>_<类型>.<ext>`，且类型与本包类别匹配；
     * 规则外（`..`、绝对路径、不认识的命名/扩展名）一律**拒绝且不落盘**。
     */
    private fun packAllowed(path: String, kind: String): Boolean {
        if (path.isEmpty() || path.contains("..") || path.startsWith("/") || path.contains(":")) {
            return false
        }
        val normalized =
            if (path.startsWith("Hymn_Downloads/")) path else "Hymn_Downloads/$path"
        val name = normalized.substringAfterLast('/')
        if (name.isEmpty()) return false
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext !in setOf("m4a", "mp3", "png")) return false
        if (!Regex("^[0-9]+(_b)?_").containsMatchIn(name)) return false
        return when (kind) {
            "scores" -> ext == "png" && (name.contains("简谱") || name.contains("五线谱"))
            "piano" -> ext != "png" && name.contains("鋼琴版")
            "vocal" -> ext != "png" && (name.contains("人聲版") || name.contains("合唱"))
            else -> false
        }
    }

    /** 解析 `ECHOHYMN-MANIFEST.json` → `{zip内路径: sha256}` */
    private fun parseManifest(text: String): Map<String, String>? {
        val array = try {
            JSONObject(text).optJSONArray("files")
        } catch (_: Exception) {
            null
        } ?: return null
        val map = HashMap<String, String>()
        for (i in 0 until array.length()) {
            try {
                val item = array.getJSONObject(i)
                val path = item.optString("path")
                val sha = item.optString("sha256")
                if (path.isNotEmpty() && sha.isNotEmpty()) map[path] = sha
            } catch (_: Exception) {
            }
        }
        return if (map.isNotEmpty()) map else null
    }

    /** 保存清单副本，供「素材自检」使用（`files/pack_manifests/<name>.json`） */
    private fun saveManifest(root: File, text: String) {
        try {
            val dir = File(root, "pack_manifests")
            dir.mkdirs()
            val name = try {
                JSONObject(text).optString("name")
            } catch (_: Exception) {
                ""
            }
            val safe = name.ifEmpty { "pack-${System.currentTimeMillis()}" }
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
            File(dir, "$safe.json").writeText(text)
        } catch (_: Exception) {
        }
    }

    /**
     * 写临时文件 → 边写边算 SHA-256 → 与清单比对 → 通过才 rename（覆盖同名）。
     * 返回 `ok` / `corrupt`（哈希不符）/ `error`（IO 失败）。
     */
    private fun writeWithCheck(zip: ZipInputStream, target: File, expectSha: String?): String {
        val tmp = File(target.parentFile, target.name + ".tmp")
        return try {
            target.parentFile?.mkdirs()
            val digest = MessageDigest.getInstance("SHA-256")
            tmp.outputStream().use { out ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    val read = zip.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                    out.write(buffer, 0, read)
                }
            }
            if (expectSha != null) {
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (!actual.equals(expectSha, ignoreCase = true)) {
                    tmp.delete()
                    return "corrupt"
                }
            }
            if (target.exists()) target.delete()
            if (tmp.renameTo(target)) "ok" else "error"
        } catch (_: Exception) {
            tmp.delete()
            "error"
        }
    }

    /** 全量素材自检：按已保存清单核对存在性与 SHA-256 */
    private fun verifyInstalled(root: File): Map<String, Any> {
        var checked = 0
        var ok = 0
        var missing = 0
        var corrupt = 0
        val details = ArrayList<String>()
        val dir = File(root, "pack_manifests")
        dir.listFiles()?.forEach { file ->
            try {
                val array = JSONObject(file.readText()).optJSONArray("files") ?: return@forEach
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val rel = item.getString("path")
                    val expect = item.getString("sha256")
                    val target = File(root, rel)
                    checked++
                    if (!target.exists()) {
                        missing++
                        if (details.size < 20) details.add("缺失：$rel")
                        continue
                    }
                    if (sha256File(target).equals(expect, ignoreCase = true)) {
                        ok++
                    } else {
                        corrupt++
                        if (details.size < 20) details.add("损坏：$rel")
                    }
                }
            } catch (_: Exception) {
            }
        }
        return mapOf(
            "checked" to checked,
            "ok" to ok,
            "missing" to missing,
            "corrupt" to corrupt,
            "details" to details
        )
    }

    private fun sha256File(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val REQ_TREE = 2001
        private const val REQ_ZIP = 2002
        private const val MANIFEST_NAME = "ECHOHYMN-MANIFEST.json"
    }
}
