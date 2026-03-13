package com.parksense.api

import android.graphics.Bitmap
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

data class ParkingResult(
    val canPark: Boolean?,
    val message: String,
    val notes: List<String>,
    val signs: List<String>,
)

data class UserProfile(
    val id: Int,
    val email: String,
    val vehicleType: String,
    val isDisabled: Boolean,
    val hasResidentPermit: Boolean,
    val residentZone: String,
)

object ApiClient {

    var serverUrl = "http://192.168.68.101:8000"
    var authToken: String? = null

    // ── Auth calls ────────────────────────────────────────────────────────────

    fun login(email: String, password: String): Pair<String, UserProfile> {
        val body = JSONObject().apply {
            put("email", email)
            put("password", password)
        }
        val response = post("/api/auth/login", body.toString(), contentType = "application/json")
        return parseAuthResponse(response)
    }

    fun register(
        email: String,
        password: String,
        vehicleType: String,
        isDisabled: Boolean,
        hasResidentPermit: Boolean,
        residentZone: String,
    ): Pair<String, UserProfile> {
        val body = JSONObject().apply {
            put("email", email)
            put("password", password)
            put("vehicle_type", vehicleType)
            put("is_disabled", isDisabled)
            put("has_resident_permit", hasResidentPermit)
            put("resident_zone", residentZone)
        }
        val response = post("/api/auth/register", body.toString(), contentType = "application/json", expectedCode = 201)
        return parseAuthResponse(response)
    }

    fun updateProfile(
        vehicleType: String,
        isDisabled: Boolean,
        hasResidentPermit: Boolean,
        residentZone: String,
    ): UserProfile {
        val body = JSONObject().apply {
            put("vehicle_type", vehicleType)
            put("is_disabled", isDisabled)
            put("has_resident_permit", hasResidentPermit)
            put("resident_zone", residentZone)
        }
        val response = put("/api/auth/me", body.toString())
        return parseUserProfile(JSONObject(response))
    }

    // ── Analysis ──────────────────────────────────────────────────────────────

    fun analyze(bitmap: Bitmap, dayName: String, timeStr: String): ParkingResult {
        val jpeg = bitmapToJpegBytes(bitmap)

        val boundary = "----ParkSenseBoundary"
        val baos = ByteArrayOutputStream()
        fun write(s: String) = baos.write(s.toByteArray())

        // image field
        write("--$boundary\r\n")
        write("Content-Disposition: form-data; name=\"image\"; filename=\"sign.jpg\"\r\n")
        write("Content-Type: image/jpeg\r\n\r\n")
        baos.write(jpeg)
        write("\r\n")

        // day field
        write("--$boundary\r\n")
        write("Content-Disposition: form-data; name=\"day\"\r\n\r\n")
        write(dayName)
        write("\r\n")

        // time field
        write("--$boundary\r\n")
        write("Content-Disposition: form-data; name=\"time\"\r\n\r\n")
        write(timeStr)
        write("\r\n")

        write("--$boundary--\r\n")

        val response = postMultipart("/api/analyze", baos.toByteArray(), boundary)
        return parseResult(response)
    }

    // ── HTTP helpers ──────────────────────────────────────────────────────────

    private fun post(
        path: String,
        body: String,
        contentType: String = "application/json",
        expectedCode: Int = 200,
    ): String {
        val conn = (URL("$serverUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", contentType)
            authToken?.let { setRequestProperty("Authorization", "Bearer $it") }
            doOutput = true
            connectTimeout = 10_000
            readTimeout = 30_000
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        return readResponse(conn, expectedCode)
    }

    private fun put(path: String, body: String): String {
        val conn = (URL("$serverUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "PUT"
            setRequestProperty("Content-Type", "application/json")
            authToken?.let { setRequestProperty("Authorization", "Bearer $it") }
            doOutput = true
            connectTimeout = 10_000
            readTimeout = 30_000
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body) }
        return readResponse(conn, 200)
    }

    private fun postMultipart(path: String, body: ByteArray, boundary: String): String {
        val conn = (URL("$serverUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            authToken?.let { setRequestProperty("Authorization", "Bearer $it") }
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 90_000
        }
        conn.outputStream.use { it.write(body) }
        return readResponse(conn, 200)
    }

    private fun readResponse(conn: HttpURLConnection, expectedCode: Int): String {
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.readText() ?: ""
        conn.disconnect()
        if (code != expectedCode) {
            val detail = runCatching { JSONObject(text).optString("detail", text) }.getOrDefault(text)
            throw Exception(detail)
        }
        return text
    }

    // ── Parsers ───────────────────────────────────────────────────────────────

    private fun parseAuthResponse(raw: String): Pair<String, UserProfile> {
        val json = JSONObject(raw)
        val token = json.getString("access_token")
        val profile = parseUserProfile(json.getJSONObject("user"))
        return token to profile
    }

    private fun parseUserProfile(json: JSONObject) = UserProfile(
        id = json.getInt("id"),
        email = json.getString("email"),
        vehicleType = json.optString("vehicle_type", "car"),
        isDisabled = json.optBoolean("is_disabled", false),
        hasResidentPermit = json.optBoolean("has_resident_permit", false),
        residentZone = json.optString("resident_zone", ""),
    )

    private fun parseResult(raw: String): ParkingResult {
        val json = JSONObject(raw)
        val canPark = if (json.isNull("can_park")) null else json.getBoolean("can_park")

        fun jsonArrayToList(key: String) = buildList {
            json.optJSONArray(key)?.let { arr ->
                for (i in 0 until arr.length()) {
                    val item = arr.get(i)
                    when (item) {
                        is JSONObject -> {
                            val text = item.optString("text", "")
                            val desc = item.optString("description", "")
                            if (text.isNotEmpty() && desc.isNotEmpty()) add("$text - $desc")
                            else if (desc.isNotEmpty()) add(desc)
                            else if (text.isNotEmpty()) add(text)
                        }
                        is String -> add(item)
                        else -> add(item.toString())
                    }
                }
            }
        }

        return ParkingResult(
            canPark = canPark,
            message = json.optString("message", ""),
            notes = jsonArrayToList("notes"),
            signs = jsonArrayToList("signs"),
        )
    }

    private fun bitmapToJpegBytes(bitmap: Bitmap): ByteArray {
        val max = 1024
        val scale = minOf(1f, max.toFloat() / maxOf(bitmap.width, bitmap.height))
        val b = if (scale < 1f)
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        else bitmap
        val out = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.JPEG, 85, out)
        if (b != bitmap) b.recycle()
        return out.toByteArray()
    }
}
