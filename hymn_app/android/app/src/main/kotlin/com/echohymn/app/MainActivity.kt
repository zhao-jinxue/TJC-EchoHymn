package com.echohymn.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * EchoHymn 主 Activity。
 *
 * 额外交付 **D-2 通知权限**通道（`echohymn/permission`）：
 * Android 13+ 需运行时授予 POST_NOTIFICATIONS，否则媒体通知 importance=NONE 不显示。
 * 不引入 permission_handler —— 其 Windows 实现依赖废弃的实验性 coroutine，会破坏桌面构建。
 */
class MainActivity : FlutterActivity() {
    private val permissionChannel = "echohymn/permission"

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
    }
}
