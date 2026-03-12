package com.parksence

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.parksence.api.ApiClient
import com.parksence.auth.LoginActivity
import com.parksence.auth.ProfileActivity
import com.parksence.auth.UserSession
import com.parksence.databinding.ActivityMainBinding
import com.parksence.detection.ColorDetector
import com.parksence.ui.ScanOverlayView
import kotlinx.coroutines.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var cameraExecutor: ExecutorService
    private var imageCapture: ImageCapture? = null
    @Volatile private var isAnalysing = false
    private var lockFrameCount = 0
    private val LOCK_FRAMES_NEEDED = 12

    private val cameraPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) startCamera() else showPermissionDenied()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        cameraExecutor = Executors.newSingleThreadExecutor()

        // Redirect to login if not authenticated
        if (!UserSession.isLoggedIn(this)) {
            startActivity(android.content.Intent(this, LoginActivity::class.java))
            finish()
            return
        }
        UserSession.load(this) // restores ApiClient.authToken

        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        ApiClient.serverUrl = prefs.getString("server_url", "http://192.168.68.101:8000")!!

        binding.btnScanAgain.setOnClickListener { resetToScan() }
        binding.btnScanAgainTop.setOnClickListener { resetToScan() }
        binding.btnSettings.setOnClickListener { showSettingsDialog() }
        val openProfile = android.content.Intent(this, ProfileActivity::class.java)
        binding.btnProfile.setOnClickListener { startActivity(openProfile) }
        binding.btnProfileScan.setOnClickListener { startActivity(openProfile) }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
            startCamera()
        else
            cameraPermission.launch(Manifest.permission.CAMERA)
    }

    // ── Settings ──────────────────────────────────────────────────────────────

    private fun showSettingsDialog() {
        val input = EditText(this).apply {
            setText(ApiClient.serverUrl)
            hint = "http://192.168.x.x:8000"
            setPadding(48, 24, 48, 24)
        }
        AlertDialog.Builder(this)
            .setTitle("Server URL")
            .setMessage("Enter your ParkSence server URL")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val url = input.text.toString().trimEnd('/')
                ApiClient.serverUrl = url
                getSharedPreferences("settings", MODE_PRIVATE).edit()
                    .putString("server_url", url).apply()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ── Camera ────────────────────────────────────────────────────────────────

    private fun startCamera() {
        ProcessCameraProvider.getInstance(this).also { future ->
            future.addListener({
                val provider = future.get()
                val preview = Preview.Builder().build()
                    .also { it.surfaceProvider = binding.previewView.surfaceProvider }

                imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .build()

                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { it.setAnalyzer(cameraExecutor, ::analyseFrame) }

                provider.unbindAll()
                provider.bindToLifecycle(
                    this, CameraSelector.DEFAULT_BACK_CAMERA,
                    preview, imageCapture, analysis
                )
            }, ContextCompat.getMainExecutor(this))
        }
    }

    // ── Live frame analysis ───────────────────────────────────────────────────

    private fun analyseFrame(proxy: ImageProxy) {
        if (isAnalysing) { proxy.close(); return }
        var hasSign = false
        try {
            var bitmap = proxy.toBitmap()
            val rotation = proxy.imageInfo.rotationDegrees
            if (rotation != 0) {
                val matrix = Matrix()
                matrix.postRotate(rotation.toFloat())
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                bitmap.recycle()
                bitmap = rotated
            }
            hasSign = ColorDetector.hasSignInCenter(bitmap)
            bitmap.recycle()
        } catch (e: Exception) {
            Log.e("ParkSence", "Frame analysis failed", e)
        } finally {
            proxy.close()
        }

        runOnUiThread {
            if (hasSign) {
                lockFrameCount++
                when {
                    lockFrameCount >= LOCK_FRAMES_NEEDED && !isAnalysing -> captureAndAnalyse()
                    lockFrameCount == 4 -> {
                        buzz()
                        binding.overlay.state = ScanOverlayView.State.LOCKED
                    }
                    lockFrameCount > 4 -> binding.overlay.state = ScanOverlayView.State.LOCKED
                }
            } else {
                lockFrameCount = 0
                if (!isAnalysing) binding.overlay.state = ScanOverlayView.State.SEARCHING
            }
        }
    }

    // ── Capture + freeze frame + LLM call ────────────────────────────────────

    private fun captureAndAnalyse() {
        isAnalysing = true
        imageCapture?.takePicture(ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: ImageProxy) {
                    val fullBitmap: Bitmap
                    try {
                        var bmp = image.toBitmap()
                        val rotation = image.imageInfo.rotationDegrees
                        if (rotation != 0) {
                            val matrix = Matrix()
                            matrix.postRotate(rotation.toFloat())
                            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                            bmp.recycle()
                            bmp = rotated
                        }
                        fullBitmap = bmp
                    } catch (e: Exception) {
                        Log.e("ParkSence", "toBitmap failed", e)
                        image.close()
                        isAnalysing = false
                        binding.overlay.state = ScanOverlayView.State.SEARCHING
                        return
                    }
                    image.close()

                    val w = fullBitmap.width
                    val h = fullBitmap.height
                    val cropX = (w * 0.31f).toInt()
                    val cropY = (h * 0.125f).toInt()
                    val cropW = (w * 0.38f).toInt()
                    val cropH = (h * 0.45f).toInt()
                    val croppedBitmap = Bitmap.createBitmap(fullBitmap, cropX, cropY, cropW, cropH)

                    showCaptureEffect(fullBitmap)

                    val now  = LocalDateTime.now()
                    val day  = now.dayOfWeek.name.lowercase().replaceFirstChar { it.uppercase() }
                    val time = now.format(DateTimeFormatter.ofPattern("HH:mm"))

                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val result = ApiClient.analyze(croppedBitmap, day, time)
                            croppedBitmap.recycle()
                            withContext(Dispatchers.Main) { showResult(result) }
                        } catch (e: Exception) {
                            croppedBitmap.recycle()
                            Log.e("ParkSence", "LM Studio call failed", e)
                            withContext(Dispatchers.Main) { showError(e.message ?: "Unknown error") }
                        }
                    }
                }
                override fun onError(exc: ImageCaptureException) {
                    Log.e("ParkSence", "Capture failed", exc)
                    isAnalysing = false
                    binding.overlay.state = ScanOverlayView.State.SEARCHING
                }
            })
    }

    // ── Persona-style capture effect ─────────────────────────────────────────

    private fun showCaptureEffect(bitmap: Bitmap) {
        buzz()

        binding.capturedFrame.setImageBitmap(bitmap)
        binding.capturedFrame.visibility = View.VISIBLE
        binding.capturedFrame.scaleX = 1.04f
        binding.capturedFrame.scaleY = 1.04f
        binding.capturedFrame.alpha = 1f
        binding.capturedFrame.animate()
            .scaleX(1f).scaleY(1f)
            .setDuration(350)
            .setInterpolator(DecelerateInterpolator())
            .start()

        binding.flashOverlay.apply {
            visibility = View.VISIBLE
            alpha = 0.8f
            animate().alpha(0f)
                .setDuration(300)
                .withEndAction { visibility = View.GONE }
                .start()
        }

        binding.overlay.state = ScanOverlayView.State.ANALYSING
    }

    // ── Haptics ──────────────────────────────────────────────────────────────

    private fun buzz() {
        try {
            val v = getSystemService(Vibrator::class.java) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                v.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(30L)
            }
        } catch (_: Exception) { }
    }

    // ── Result display ────────────────────────────────────────────────────────

    private fun showResult(result: com.parksence.api.ParkingResult) {
        // Fade out frozen frame + overlay
        binding.overlay.animate().alpha(0f).setDuration(250).withEndAction {
            binding.overlay.visibility = View.GONE
            binding.overlay.alpha = 1f
        }.start()

        binding.capturedFrame.animate()
            .alpha(0f).setDuration(300)
            .withEndAction {
                binding.capturedFrame.visibility = View.GONE
                binding.capturedFrame.setImageBitmap(null)
            }.start()

        // Hide scan-screen UI
        binding.brandingLabel.visibility = View.GONE
        binding.btnSettings.visibility = View.GONE
        binding.btnProfileScan.visibility = View.GONE

        // Slide in result card
        binding.resultCard.apply {
            alpha = 0f; translationY = 60f; visibility = View.VISIBLE
            animate().alpha(1f).translationY(0f).setDuration(400)
                .setStartDelay(100)
                .setInterpolator(DecelerateInterpolator()).start()
        }

        // Verdict card: background + icon + title + color
        when (result.canPark) {
            true -> {
                binding.verdictCard.setBackgroundResource(R.drawable.bg_verdict_can)
                binding.resultIcon.text = "\u2705"
                binding.resultTitle.text = "You can park here"
                binding.resultTitle.setTextColor(getColor(R.color.green))
            }
            false -> {
                binding.verdictCard.setBackgroundResource(R.drawable.bg_verdict_cannot)
                binding.resultIcon.text = "\uD83D\uDEAB"
                binding.resultTitle.text = "No parking here"
                binding.resultTitle.setTextColor(getColor(R.color.red))
            }
            null -> {
                binding.verdictCard.setBackgroundResource(R.drawable.bg_verdict_unknown)
                binding.resultIcon.text = "\u26A0\uFE0F"
                binding.resultTitle.text = "Could not determine"
                binding.resultTitle.setTextColor(getColor(R.color.orange))
            }
        }

        binding.resultMessage.text = result.message

        // Notes as individual cards
        binding.notesContainer.removeAllViews()
        if (result.notes.isNotEmpty()) {
            binding.notesHeader.visibility = View.VISIBLE
            result.notes.forEachIndexed { i, note ->
                val tv = TextView(this).apply {
                    text = "\u2139\uFE0F  $note"
                    textSize = 13f
                    setTextColor(0xCCFFFFFF.toInt())
                    setBackgroundResource(R.drawable.bg_notes_card)
                    setPadding(36, 22, 36, 22)
                    setLineSpacing(0f, 1.4f)
                    val lp = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = 8 }
                    layoutParams = lp
                    alpha = 0f; translationX = 40f
                    animate().alpha(1f).translationX(0f)
                        .setStartDelay((i * 60 + 200).toLong())
                        .setDuration(280).setInterpolator(DecelerateInterpolator()).start()
                }
                binding.notesContainer.addView(tv)
            }
        } else {
            binding.notesHeader.visibility = View.GONE
        }

        // Signs as individual chips
        binding.signsContainer.removeAllViews()
        if (result.signs.isNotEmpty()) {
            binding.signsHeader.visibility = View.VISIBLE
            result.signs.forEachIndexed { i, sign ->
                val tv = TextView(this).apply {
                    text = sign
                    textSize = 13f
                    setTextColor(0xBBFFFFFF.toInt())
                    setBackgroundResource(R.drawable.bg_sign_chip)
                    setPadding(28, 16, 28, 16)
                    val lp = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = 8 }
                    layoutParams = lp
                    alpha = 0f; translationX = 40f
                    animate().alpha(1f).translationX(0f)
                        .setStartDelay((i * 60 + 350).toLong())
                        .setDuration(280).setInterpolator(DecelerateInterpolator()).start()
                }
                binding.signsContainer.addView(tv)
            }
        } else {
            binding.signsHeader.visibility = View.GONE
        }

        binding.btnScanAgain.visibility = View.VISIBLE
    }

    private fun showError(msg: String) {
        isAnalysing = false
        binding.overlay.visibility = View.GONE
        binding.capturedFrame.animate()
            .alpha(0f).setDuration(200)
            .withEndAction {
                binding.capturedFrame.visibility = View.GONE
                binding.capturedFrame.setImageBitmap(null)
            }.start()

        binding.brandingLabel.visibility = View.GONE
        binding.btnSettings.visibility = View.GONE
        binding.btnProfileScan.visibility = View.GONE

        binding.resultCard.visibility = View.VISIBLE
        binding.verdictCard.setBackgroundResource(R.drawable.bg_verdict_cannot)
        binding.resultIcon.text = "\u274C"
        binding.resultTitle.text = "Connection error"
        binding.resultTitle.setTextColor(getColor(R.color.red))
        binding.resultMessage.text =
            "Could not reach the server.\n\n\u2022 Check your WiFi\n\u2022 Server is running\n\u2022 Tap \u2699 and set correct URL\n\n$msg"
        binding.btnScanAgain.visibility = View.VISIBLE
    }

    private fun resetToScan() {
        isAnalysing = false
        lockFrameCount = 0

        binding.overlay.alpha = 1f
        binding.overlay.state = ScanOverlayView.State.SEARCHING
        binding.overlay.visibility = View.VISIBLE

        binding.capturedFrame.visibility = View.GONE
        binding.capturedFrame.setImageBitmap(null)

        binding.resultCard.visibility = View.GONE
        binding.btnScanAgain.visibility = View.GONE
        binding.notesHeader.visibility = View.GONE
        binding.signsHeader.visibility = View.GONE
        binding.notesContainer.removeAllViews()
        binding.signsContainer.removeAllViews()

        binding.brandingLabel.visibility = View.VISIBLE
        binding.btnSettings.visibility = View.VISIBLE
        binding.btnProfileScan.visibility = View.VISIBLE
    }

    private fun showPermissionDenied() {
        binding.brandingLabel.visibility = View.GONE
        binding.btnSettings.visibility = View.GONE
        binding.resultCard.visibility = View.VISIBLE
        binding.verdictCard.setBackgroundResource(R.drawable.bg_verdict_unknown)
        binding.resultIcon.text = "\uD83D\uDCF7"
        binding.resultTitle.text = "Camera permission required"
        binding.resultTitle.setTextColor(getColor(R.color.orange))
        binding.resultMessage.text = "Please allow camera access in Settings."
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }
}
