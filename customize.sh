#!/system/bin/sh
# Magisk Module Customization Script (customize.sh)

# 模块ID: LSPosed_update_test
# 功能: 辅助目标模块 (zygisk_lsposed) 进行更新版本检测、交互式更新引导，以及文件保留/暂存操作。

# --- 变量定义 (Configuration Variables) ---

# 1. 目标模块信息 (Target Module: zygisk_lsposed)
TARGET_MODULE_ID="zygisk_lsposed"
TARGET_OLD_PATH="/data/adb/modules/$TARGET_MODULE_ID"              # 目标模块的当前安装路径
TARGET_STAGING_PATH="/data/adb/modules_update/$TARGET_MODULE_ID" # 目标模块的更新暂存路径

# 2. 本辅助模块信息 (Assistant Module: LSPosed_update_test)
ASSISTANT_MODULE_ID="LSPosed_update_test"

# 3. 版本和链接配置 (Version and Link Configuration)
# 获取目标模块的当前已安装版本号
CURRENT_VER_CODE=$(grep ^versionCode= "$TARGET_OLD_PATH/module.prop" 2>/dev/null | cut -d= -f2)
if [ -z "$CURRENT_VER_CODE" ]; then
    CURRENT_VER_CODE=0
fi
#版本号/更新链接/模块更新标识
LATEST_VER_URL="https://raw.githubusercontent.com/YFTree/LSPosed_update_test/refs/heads/main/update.json"
TG_DOWNLOAD_LINK="https://t.me/LSPosed_bot?start=dl"
TARGET_UPDATE_FLAG_FILE="$TARGET_STAGING_PATH/update" # Magisk 更新标识文件
SET_TARGET_UPDATE_FLAG_FILE="$TARGET_OLD_PATH/update"

# 4. 音量键常量 (Volume Key Constants)
KEY_UP="KEY_VOLUMEUP"
KEY_DOWN="KEY_VOLUMEDOWN"

# 5. 全局控制开关 (Global Control Switch)
SKIP_COPY_FILES=false # 控制是否跳过文件保留/暂存逻辑

# ---------------------------------------------
# 🔥 仅修改此部分以适配 JSON 解析 🔥
# ---------------------------------------------
# 获取最新版本号 (适配 JSON 格式)
ui_print "🔍 正在从服务器 ($LATEST_VER_URL) 读取 JSON 版本信息..."

# 原始脚本的 curl 被替换为更健壮的 JSON 解析逻辑
LATEST_JSON=$(curl -s "$LATEST_VER_URL")

if [ $? -ne 0 ] || [ -z "$LATEST_JSON" ]; then
    ui_print "⚠️ 警告：无法连接到服务器或获取 JSON 内容。"
    LATEST_VER_CODE=0
else
    # 使用 Awk 提取 "versionCode" 的值 (适用于单行 JSON 格式)
    LATEST_VER_CODE=$(echo "$LATEST_JSON" | awk -F ',' '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /"versionCode"/) {
                split($i, a, ":");
                # 提取数值部分 (a[2])，并去除所有非数字字符
                gsub(/[^0-9]/, "", a[2]);
                print a[2];
                exit;
            }
        }
    }')
fi

# 最终检查和设置 LATEST_VER_CODE
if [ -z "$LATEST_VER_CODE" ]; then
    ui_print "❌ 错误：无法从 JSON 内容中解析出有效的 versionCode。"
    LATEST_VER_CODE=0
else
    # 移除可能的换行符，确保是纯数字
    LATEST_VER_CODE=$(echo "$LATEST_VER_CODE" | tr -d '\r')
    ui_print "✅ 服务器最新版本号: **$LATEST_VER_CODE**"
fi
# ---------------------------------------------
# ---------------------------------------------

# --- 辅助函数：音量键获取 (Helper Function: Capture Volume Button Press) ---
# 使用 getevent 捕获一次音量键按键输入
get_button() {
    button=""
    ui_print "等待按键..."
    while [ "$button" = "" ]; do
        # getevent -qlc 1: 静默捕获 1 个长格式事件
        button="$(getevent -qlc 1 | awk '{ print $3 }' | grep 'KEY_VOLUME')"
        sleep 0.2
    done
}

# --- 1. 交互式问答逻辑 (Interactive Quiz and Interruption Logic) ---

interactive_quiz() {
    ui_print " "
    ui_print "****************************************"
    ui_print "🚨 **重要更新提示/内测包警告** 🚨"
    ui_print "     目标模块版本: $CURRENT_VER_CODE"
    # 注意: LATEST_VER_CODE 在 check_for_update_and_warn 中获取并设置
    ui_print "     服务器最新版本: $LATEST_VER_CODE"
    ui_print " "
    ui_print "⚠️ **【内测包重要警告】** ⚠️"
    ui_print "     此模块为内测版本，严禁公开分享或传播！"
    ui_print " "
    ui_print "请根据提示按动音量键选择"

    local rule_confirmed=false
    local update_chosen=false
    local exit_reason=""

    # --- 第一题：确认规则 (Rule Confirmation) ---
    local confirm_key_code=$(( $RANDOM % 2 ))
    local confirm_option="✅ 我清楚并明白内测包更新规则"
    local cancel_option="❌ 我不清楚"

    local required_key_1=""
    if [ "$confirm_key_code" -eq 0 ]; then
        required_key_1="$KEY_UP"
        ui_print "--- 第一题 (请按音量键) ---"
        ui_print "🔊 上键: $confirm_option"
        ui_print "🔇 下键: $cancel_option"
    else
        required_key_1="$KEY_DOWN"
        ui_print "--- 第一题 (请按音量键) ---"
        ui_print "🔊 上键: $cancel_option"
        ui_print "🔇 下键: $confirm_option"
    fi

    get_button
    local selected_key_1="$button"

    # 检查第一题结果
    if [ "$selected_key_1" = "$required_key_1" ]; then
        rule_confirmed=true
    fi

    # --- 第二题：跳转更新 (Update Selection) ---
    local update_key_code=$(( $RANDOM % 2 ))
    local update_option="🚀 跳转到 Telegram 机器人更新"
    local install_option="❌ 拒绝更新"

    local required_key_2=""
    ui_print " "
    ui_print "--- 第二题 (请按音量键) ---"
    if [ "$update_key_code" -eq 0 ]; then
        required_key_2="$KEY_UP"
        ui_print "🔊 上键 ($KEY_UP): $update_option"
        ui_print "🔇 下键 ($KEY_DOWN): $install_option"
    else
        required_key_2="$KEY_DOWN"
        ui_print "🔊 上键 ($KEY_UP): $install_option"
        ui_print "🔇 下键 ($KEY_DOWN): $update_option"
    fi

    get_button
    local selected_key_2="$button"

    # 检查第二题结果
    if [ "$selected_key_2" = "$required_key_2" ]; then
        update_chosen=true
    else
        # 如果确认规则但拒绝更新，则设置退出原因
        if [ "$rule_confirmed" = true ]; then
            exit_reason="REFUSED_UPDATE"
        fi
    fi

    # --- 最终行动和中断检查 (Final Action and Interruption) ---
    ui_print " "
    if [ "$rule_confirmed" = true ] && [ "$update_chosen" = true ]; then
        # 成功路径：执行更新链接启动
        ui_print "✅ 已选择跳转更新。尝试启动浏览器..."
        # 使用 Activity Manager (am) 启动 VIEW action 跳转到 Telegram 链接
        am start -a android.intent.action.VIEW -d "$TG_DOWNLOAD_LINK" >/dev/null 2>&1
        
        # 新增逻辑：模块正常跳转/展示更新链接后，设置跳过文件复制的开关
        SKIP_COPY_FILES=true
        
        if [ $? -eq 0 ]; then
            ui_print "🚀 浏览器已尝试启动。请稍后检查手机屏幕。"
        else
            ui_print "❌ 警告：'am' 启动失败或当前环境不支持。请手动复制链接。（你有10s的时间）"
            sleep 10s
        fi
        ui_print "🔗 更新链接: $TG_DOWNLOAD_LINK"
        ui_print "****************************************"
    
    elif [ -n "$exit_reason" ] || [ "$rule_confirmed" = false ]; then
        # 失败/中断路径：打印警告并中断安装
        if [ "$rule_confirmed" = false ]; then
             exit_reason="UNCORFIRMED_RULES" # 如果未确认规则，设置退出原因
        fi
        
        ui_print "****************************************"
        ui_print "🚫 🚨 **安装中断警告** 🚨 🚫"

        if [ "$exit_reason" = "UNCORFIRMED_RULES" ]; then
            ui_print "🤔 看来您不太喜欢阅读重要的提示，或者习惯性乱点。"
            ui_print "❌ 为了保护内测包的安全，以及不让不看提示的**傻逼**污染环境，安装程序已停止。"
            ui_print "➡️ 请重新仔细阅读提示，并按正确的音量键确认后再尝试安装。"
        elif [ "$exit_reason" = "REFUSED_UPDATE" ]; then
            ui_print "🤡 **选择了跳过/拒绝更新？**看来你对内测版本的意义理解不深。"
            ui_print "❌ 内测包的核心价值在于迭代。不更新，就别用。"
            ui_print "➡️ 请重新安装并选择更新选项，否则你就是**傻逼**。"
        fi

        ui_print "****************************************"
        exit 1 # 立即停止安装
    fi
}

# ---------------------------------------------
# 🚨 更新检测和警告函数 (Update Check and Warning Function) 🚨
check_for_update_and_warn() {
    ui_print " "
    ui_print "🔍 正在检测模块更新..."

    # 检查 curl 命令是否存在
    if ! command -v curl >/dev/null 2>&1; then
        ui_print "⚠️ 警告：系统未安装 'curl' 命令，无法进行更新检测。"
        return 1
    fi
    
    # 【注意】原脚本中 LATEST_VER_CODE 已经在开头获取，这里不重复获取
    
    # 检查版本号是否有效（防止 JSON 解析失败导致比较错误）
    if [ "$LATEST_VER_CODE" -eq 0 ]; then
         ui_print "⚠️ 警告：无法获取或解析最新版本号，跳过更新检测交互。"
         return 1
    fi

    # --- 版本比较逻辑 (Version Comparison) ---
    if [ "$LATEST_VER_CODE" -gt "$CURRENT_VER_CODE" ]; then
        # 情况 1: 需要更新 -> 启动交互式问答
        interactive_quiz

    elif [ "$LATEST_VER_CODE" -eq "$CURRENT_VER_CODE" ]; then
        # 情况 2: 已是最新版本
        ui_print "🎉 模块版本: $CURRENT_VER_CODE"
        ui_print "✅ 已是最新内测版本，无需更新。请静待下一次版本发布！"

    else
        # 情况 3: 当前安装包版本更高 (可能存在包来源问题)
        ui_print " "
        ui_print "⚠️ **【版本警告】** ⚠️"
        ui_print "     当前安装包版本 ($CURRENT_VER_CODE) 比服务器最新版本 ($LATEST_VER_CODE) **更高**。"
        ui_print "     请确认包的来源是否正确。安装将继续。"
        ui_print " "
    fi
    return 0
}
# ---------------------------------------------


# --- 2. 核心文件复制和清理函数 (Core File Management Functions) ---

## 2.1 清理本辅助模块 (LSPosed_update_test) 的旧路径
# 移除本辅助模块残留的安装或暂存目录，确保“用完即走”
cleanup_assistant_module() {
    ui_print " "
    ui_print "🧹 正在清理本模块（$ASSISTANT_MODULE_ID）的旧安装路径..."

    # 清理已安装路径
    if [ -d "/data/adb/modules/$ASSISTANT_MODULE_ID" ]; then
        rm -rf "/data/adb/modules/$ASSISTANT_MODULE_ID"
        ui_print "✅ 已删除旧的已安装路径: /data/adb/modules/$ASSISTANT_MODULE_ID"
    fi

    # 清理更新暂存路径
    if [ -d "/data/adb/modules_update/$ASSISTANT_MODULE_ID" ]; then
        rm -rf "/data/adb/modules_update/$ASSISTANT_MODULE_ID"
        ui_print "✅ 已删除旧的暂存路径: /data/adb/modules_update/$ASSISTANT_MODULE_ID"
    fi

    # 清理当前安装的 MODPATH (谨慎操作，通常 Magisk 会处理临时目录)
    if [ -d "$MODPATH" ]; then
        rm -rf "$MODPATH"
        ui_print "⚠️ 警告：已尝试删除本模块当前的临时安装路径 ($MODPATH)。"
    fi

    ui_print "清理本模块流程完成。"
    return 0
}

## 2.2 复制/暂存目标模块 (zygisk_lsposed) 的旧文件
# 将目标模块的现有安装文件备份到 Magisk 更新暂存区，以便保留用户配置
copy_target_module_files() {
    ui_print " "
    ui_print "🔄 正在执行目标模块（$TARGET_MODULE_ID）文件保留和暂存..."

    if [ ! -d "$TARGET_OLD_PATH" ]; then
        ui_print "ℹ️ 目标模块路径 $TARGET_OLD_PATH 不存在，跳过文件保留/迁移。"
        return 0
    fi

    # 双重检查路径是否存在
    if [ ! -d "$TARGET_OLD_PATH" ]; then
        ui_print "ℹ️ 目标模块路径 $TARGET_OLD_PATH 不存在，跳过文件保留/迁移。"
        return 0
    fi

    # 清理旧的暂存目录
    if [ -d "$TARGET_STAGING_PATH" ]; then
        ui_print "    清理目标模块旧暂存目录 $TARGET_STAGING_PATH..."
        rm -rf "$TARGET_STAGING_PATH"
    fi

    ui_print "    从 $TARGET_OLD_PATH 复制文件到更新区 $TARGET_STAGING_PATH..."
    # 确保父目录存在
    mkdir -p "$(dirname "$TARGET_STAGING_PATH")" 2>/dev/null
    # 使用 cp -af 复制目录和权限
    cp -af "$TARGET_OLD_PATH" "$TARGET_STAGING_PATH"

    if [ $? -ne 0 ]; then
        ui_print "❌ 错误：复制目标模块文件失败！文件保留机制失败！"
        return 1
    fi

    # 删除目标模块更新标识文件
    if [ -f "$TARGET_UPDATE_FLAG_FILE" ]; then
        ui_print "    删除目标模块更新标识文件 $TARGET_UPDATE_FLAG_FILE..."
        rm -f "$TARGET_UPDATE_FLAG_FILE"
    fi

    # 创建目标模块更新标识文件
    if [ -!f "$SET_TARGET_UPDATE_FLAG_FILE" ]; then
        ui_print "    创建目标模块更新标识文件 $SET_TARGET_UPDATE_FLAG_FILE..."
        touch "$SET_TARGET_UPDATE_FLAG_FILE"
    fi
    ui_print "✅ 文件保留/暂存完成。目标模块配置已安全保留。"
    return 0
}


# --- 主执行流程 (Main Execution Flow) ---

# 1. 清理本辅助模块自身路径
#cleanup_assistant_module

# 2. 执行更新检测和交互
check_for_update_and_warn


# 3. 执行目标模块的文件复制和暂存
# 检查 SKIP_COPY_FILES 开关
#if [[ "$SKIP_COPY_FILES" = true && "$LATEST_VER_CODE" = 0 ]]; then
    ui_print " "
#    ui_print "⏭️ 检测到用户选择更新，跳过目标模块的文件保留和暂存操作。"
#else
#    copy_target_module_files
#fi


ui_print " "
# 使用 echo 输出 114514 报错码和梗
echo -e "💣 安装已成功完成，但我们决定给你一个惊喜。"
echo -e "🚨 ERROR: 114514 (哼，嗯！啊啊啊啊啊啊！！！)"
exit 1