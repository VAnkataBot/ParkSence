package com.parksence.auth

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.parksence.MainActivity
import com.parksence.api.ApiClient
import com.parksence.databinding.ActivityLoginBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class LoginActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLoginBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Skip login if already authenticated
        if (UserSession.isLoggedIn(this)) {
            UserSession.load(this)
            goToMain()
            return
        }

        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val hintColor = 0x44FFFFFF.toInt()
        binding.etEmail.setHintTextColor(hintColor)
        binding.etPassword.setHintTextColor(hintColor)

        binding.btnLogin.setOnClickListener { doLogin() }
        binding.btnGoRegister.setOnClickListener {
            startActivity(Intent(this, RegisterActivity::class.java))
        }
    }

    private fun doLogin() {
        val email = binding.etEmail.text.toString().trim()
        val password = binding.etPassword.text.toString()

        if (email.isEmpty() || password.isEmpty()) {
            showError("Please fill in all fields")
            return
        }

        setLoading(true)

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val (token, profile) = ApiClient.login(email, password)
                withContext(Dispatchers.Main) {
                    UserSession.save(this@LoginActivity, token, profile)
                    goToMain()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setLoading(false)
                    showError(e.message ?: "Login failed")
                }
            }
        }
    }

    private fun goToMain() {
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }

    private fun showError(msg: String) {
        binding.tvError.text = msg
        binding.tvError.visibility = View.VISIBLE
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnLogin.isEnabled = !loading
        binding.tvError.visibility = View.GONE
    }
}
