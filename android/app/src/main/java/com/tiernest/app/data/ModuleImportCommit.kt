package com.tiernest.app.data

object ModuleImportCommit {
    fun commit(
        oldConfig: String,
        newConfig: String,
        oldPrefs: Preferences,
        newPrefs: Preferences,
        writeConfig: (String) -> Unit,
        writePrefs: ((Preferences) -> Preferences) -> Preferences,
    ): Preferences {
        require(newPrefs.migrationReview.isNotBlank()) { "导入偏好必须包含迁移审阅信息" }
        require(!newPrefs.requested) { "导入偏好必须保持手动停止状态" }

        // 1. 先持久化新导入偏好（门禁与停止状态先行）
        val committedPrefs = writePrefs { current ->
            current.copy(
                requested = false,
                automatic = newPrefs.automatic,
                detection = newPrefs.detection,
                interval = newPrefs.interval,
                homes = newPrefs.homes,
                migrationReview = newPrefs.migrationReview,
            )
        }

        // 2. 再写 TOML 配置
        try {
            writeConfig(newConfig)
        } catch (configError: Throwable) {
            // 配置写入抛错时主动尝试恢复 oldConfig
            try {
                writeConfig(oldConfig)
            } catch (rollbackConfigError: Throwable) {
                // 配置恢复失败时保留迁移门禁/停止状态，把回滚异常加 suppressed 再抛原错误
                configError.addSuppressed(rollbackConfigError)
                throw configError
            }

            // 仅配置恢复成功后，再恢复旧导入偏好且 requested 固定 false
            try {
                writePrefs { current ->
                    current.copy(
                        requested = false,
                        automatic = oldPrefs.automatic,
                        detection = oldPrefs.detection,
                        interval = oldPrefs.interval,
                        homes = oldPrefs.homes,
                        migrationReview = oldPrefs.migrationReview,
                    )
                }
            } catch (rollbackPrefError: Throwable) {
                // 恢复偏好失败同样保留原错误并附加异常
                configError.addSuppressed(rollbackPrefError)
            }

            throw configError
        }

        return committedPrefs
    }
}
