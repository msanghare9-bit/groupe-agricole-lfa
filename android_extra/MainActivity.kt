package sn.lfakebemer.groupeagricole

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lfarm/installateur")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dossier" -> result.success(cacheDir.absolutePath)
                    "installer" -> {
                        try {
                            val chemin = call.argument<String>("chemin")!!
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fichiers", File(chemin)
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERREUR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
