package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@androidx.annotation.OptIn(markerClass = [androidx.camera.core.ExperimentalGetImage::class])
class WatchQrScannerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val preview: PreviewView
    private val status: android.widget.TextView
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val handled = AtomicBoolean(false)
    private var cameraProvider: ProcessCameraProvider? = null
    private var scanner = BarcodeScanning.getClient()
    private var onResult: ((String) -> Unit)? = null

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_qr_scanner_view, this, true)
        preview = findViewById(R.id.watch_scan_preview)
        status = findViewById(R.id.watch_scan_status)
    }

    fun setOnResult(action: (String) -> Unit) { onResult = action }

    fun start(owner: LifecycleOwner) {
        handled.set(false)
        status.visibility = GONE
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            val provider = providerFuture.get()
            cameraProvider = provider
            val cameraPreview = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { useCase ->
                    useCase.setAnalyzer(cameraExecutor) { imageProxy ->
                        val mediaImage = imageProxy.image
                        if (mediaImage == null || handled.get()) {
                            imageProxy.close()
                            return@setAnalyzer
                        }
                        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
                        scanner.process(image)
                            .addOnSuccessListener { codes ->
                                val value = codes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
                                if (!value.isNullOrBlank() && handled.compareAndSet(false, true)) {
                                    post {
                                        status.text = context.getString(R.string.watch_scan_found, value)
                                        status.visibility = VISIBLE
                                        onResult?.invoke(value)
                                    }
                                }
                            }
                            .addOnCompleteListener { imageProxy.close() }
                    }
                }
            provider.unbindAll()
            provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, cameraPreview, analysis)
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        cameraProvider?.unbindAll()
        cameraProvider = null
        handled.set(true)
    }

    fun showPermissionDenied() {
        status.text = context.getString(R.string.watch_scan_permission_denied)
        status.visibility = VISIBLE
    }

    override fun onDetachedFromWindow() {
        stop()
        cameraExecutor.shutdown()
        scanner.close()
        super.onDetachedFromWindow()
    }
}
