package com.parksence.auth

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.parksence.MainActivity
import com.parksence.R
import com.parksence.api.ApiClient
import com.parksence.databinding.ActivityRegisterBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RegisterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRegisterBinding
    private var selectedVehicle = "car"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRegisterBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val hintColor = 0x44FFFFFF.toInt()
        binding.etEmail.setHintTextColor(hintColor)
        binding.etPassword.setHintTextColor(hintColor)
        binding.etResidentZone.setHintTextColor(hintColor)

        binding.btnBack.setOnClickListener { finish() }
        binding.btnRegister.setOnClickListener { doRegister() }

        // Vehicle type buttons
        val vehicleButtons = listOf(
            "car" to binding.btnVehicleCar,
            "motorcycle" to binding.btnVehicleMoto,
            "ev" to binding.btnVehicleEV,
            "truck" to binding.btnVehicleTruck,
        )
        vehicleButtons.forEach { (type, btn) ->
            btn.setOnClickListener {
                selectedVehicle = type
                vehicleButtons.forEach { (_, b) -> b.setBackgroundResource(R.drawable.bg_vehicle_unselected) }
                btn.setBackgroundResource(R.drawable.bg_vehicle_selected)
            }
        }

        // Resident permit toggle shows/hides zone input
        binding.switchResident.setOnCheckedChangeListener { _, checked ->
            binding.residentZoneRow.visibility = if (checked) View.VISIBLE else View.GONE
        }
    }

    private fun doRegister() {
        val email = binding.etEmail.text.toString().trim()
        val password = binding.etPassword.text.toString()

        if (email.isEmpty()) { showError("Email is required"); return }
        if (password.length < 6) { showError("Password must be at least 6 characters"); return }

        val isDisabled = binding.switchDisabled.isChecked
        val hasResident = binding.switchResident.isChecked
        val zone = binding.etResidentZone.text.toString().trim()

        setLoading(true)

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val (token, profile) = ApiClient.register(
                    email = email,
                    password = password,
                    vehicleType = selectedVehicle,
                    isDisabled = isDisabled,
                    hasResidentPermit = hasResident,
                    residentZone = zone,
                )
                withContext(Dispatchers.Main) {
                    UserSession.save(this@RegisterActivity, token, profile)
                    goToMain()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setLoading(false)
                    showError(e.message ?: "Registration failed")
                }
            }
        }
    }

    private fun goToMain() {
        startActivity(Intent(this, MainActivity::class.java))
        finishAffinity()
    }

    private fun showError(msg: String) {
        binding.tvError.text = msg
        binding.tvError.visibility = View.VISIBLE
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnRegister.isEnabled = !loading
        binding.tvError.visibility = View.GONE
    }
}
