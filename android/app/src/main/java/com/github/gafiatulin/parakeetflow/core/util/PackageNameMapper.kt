package com.github.gafiatulin.parakeetflow.core.util

import android.content.Context
import android.content.pm.PackageManager

object PackageNameMapper {

    fun getAppLabel(context: Context, packageName: String): String {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName.substringAfterLast('.')
        }
    }
}
