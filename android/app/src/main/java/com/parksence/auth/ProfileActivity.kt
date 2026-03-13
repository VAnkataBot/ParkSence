package com.parksense.auth

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.parksense.R
import com.parksense.api.ApiClient
import com.parksense.api.UserProfile
import com.parksense.databinding.ActivityProfileBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ProfileActivity : AppCompatActivity() {

    private lateinit var binding: ActivityProfileBinding
    private var selectedVehicle = "car"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProfileBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.etResidentZone.setHintTextColor(0x44FFFFFF.toInt())

        binding.btnClose.setOnClickListener { finish() }
        binding.btnSave.setOnClickListener { doSave() }
        binding.btnLogout.setOnClickListener { doLogout() }

        // Load current profile
        val profile = UserSession.load(this)
        if (profile != null) {
            binding.tvEmail.text = profile.email
            selectedVehicle = profile.vehicleType
            refreshVehicleButtons()
            binding.switchDisabled.isChecked = profile.isDisabled
            binding.switchResident.isChecked = profile.hasResidentPermit
            if (profile.hasResidentPermit) {
                binding.residentZoneRow.visibility = View.VISIBLE
                binding.etResidentZone.setText(profile.residentZone)
            }
        }

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

        binding.switchResident.setOnCheckedChangeListener { _, checked ->
            binding.residentZoneRow.visibility = if (checked) View.VISIBLE else View.GONE
        }
    }

    private fun refreshVehicleButtons() {
        val map = mapOf(
            "car" to binding.btnVehicleCar,
            "motorcycle" to binding.btnVehicleMoto,
            "ev" to binding.btnVehicleEV,
            "truck" to binding.btnVehicleTruck,
        )
        map.forEach { (type, btn) ->
            btn.setBackgroundResource(
                if (type == selectedVehicle) R.drawable.bg_vehicle_selected
                else R.drawable.bg_vehicle_unselected
            )
        }
    }

    private fun doSave() {
        setLoading(true)
        val isDisabled = binding.switchDisabled.isChecked
        val hasResident = binding.switchResident.isChecked
        val zone = binding.etResidentZone.text.toString().trim()

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val updated = ApiClient.updateProfile(
                    vehicleType = selectedVehicle,
                    isDisabled = isDisabled,
                    hasResidentPermit = hasResident,
                    residentZone = zone,
                )
                withContext(Dispatchers.Main) {
                    UserSession.updateProfile(this@ProfileActivity, updated)
                    setLoading(false)
                    finish()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setLoading(false)
                    // TODO: show toast/snackbar
                }
            }
        }
    }

    private fun doLogout() {
        UserSession.logout(this)
        startActivity(Intent(this, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnSave.isEnabled = !loading
    }
}
