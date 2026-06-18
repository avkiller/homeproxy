#!/bin/sh

# ====================================================================
# 配置区域
# ====================================================================
SERVER_URL="http://192.168.3.106:5000/homeproxy"

FILE_UPDATE="/etc/homeproxy/scripts/update_homeproxy.sh"
FILE_UC="/etc/homeproxy/scripts/generate_client.uc"
FILE_CLIENT_JS="/www/luci-static/resources/view/homeproxy/client.js"
FILE_HOMEPROXY_JS="/www/luci-static/resources/homeproxy.js"

# ====================================================================
# 函数定义：支持不存在直接下载、存在则备份还原
# ====================================================================
download_and_restore() {
    local target_file="$1"
    local download_url="$2"
    local bak_file="${target_file}.bak"

    # 【核心逻辑修改】如果文件不存在，直接下载，不执行备份和属性提取
    if [ ! -f "$target_file" ]; then
        echo "   [提示] $target_file 不存在，无需备份，正在直接全新下载..."
        wget -O "$target_file" "$download_url"
        
        if [ $? -eq 0 ]; then
            echo "   [成功] 文件全新下载成功！"
            # 如果是 uc 脚本文件，全新下载时默认赋予 755 可执行权限以防报错
            if [ "${target_file##*.}" = "uc" || "${target_file##*.}" = "sh" ]; then
                chmod 755 "$target_file"
                echo "   [权限] 已自动为新脚本赋予 755 可执行权限"
            fi
            return 0
        else
            echo "   [错误] 全新下载失败，请检查网络或远程服务器！"
            return 1
        fi
    fi

    # ----------------------------------------------------------------
    # 以下为【文件存在】时的备份与覆盖逻辑
    # ----------------------------------------------------------------
    # 1. 备份原文件为 .bak
    cp -p "$target_file" "$bak_file"
    echo "   [备份] 已将原文件备份至 $bak_file (已保留原属性)"

    # 2. 使用 ls 和 awk 动态获取原文件的所有者和组（如 root:root）
    local orig_owner=$(ls -l "$target_file" | awk '{print $3":"$4}')
    
    # 3. 动态获取原文件的三位数字权限（如 755 / 644）
    local orig_perms=$(ls -l "$target_file" | awk '{
        perms=$1;
        val=0;
        if (substr(perms,2,1)=="r") val+=400; if (substr(perms,3,1)=="w") val+=200; if (substr(perms,4,1)=="x") val+=100;
        if (substr(perms,5,1)=="r") val+=40;  if (substr(perms,6,1)=="w") val+=20;  if (substr(perms,7,1)=="x") val+=10;
        if (substr(perms,8,1)=="r") val+=4;   if (substr(perms,9,1)=="w") val+=2;   if (substr(perms,10,1)=="x") val+=1;
        printf "%03d", val;
    }')

    # 4. 执行下载覆盖
    wget -O "$target_file" "$download_url"
    
    if [ $? -eq 0 ]; then
        echo "   [成功] 已成功下载并覆盖 $target_file"
        # 5. 完美还原新覆盖文件的属性
        chmod "$orig_perms" "$target_file"
        chown "$orig_owner" "$target_file"
        echo "   [属性还原] 新文件权限已恢复为 $orig_perms ($orig_owner)"
        return 0
    else
        echo "   [错误] 下载覆盖失败！"
        echo "   [回滚提示] 如需还原旧文件，请执行: cp -p $bak_file $target_file"
        return 1
    fi
}

# ====================================================================
# 执行区域
# ====================================================================
echo "=========================================="
echo "开始更新 Homeproxy 相关文件..."
echo "=========================================="

# 处理 update_homeproxy.sh
echo "-> 正在处理 update_homeproxy.sh..."
download_and_restore "$FILE_UPDATE" "${SERVER_URL}/update_homeproxy.sh"

# 处理 generate_client.uc
echo "-> 正在处理 generate_client.uc..."
download_and_restore "$FILE_UC" "${SERVER_URL}/generate_client.uc"

echo "------------------------------------------"

# 处理 homeproxy.js
echo "-> 正在处理 homeproxy.js..."
download_and_restore "$FILE_HOMEPROXY_JS" "${SERVER_URL}/homeproxy.js"

echo "------------------------------------------"

# 处理 client.js
echo "-> 正在处理 client.js..."
download_and_restore "$FILE_CLIENT_JS" "${SERVER_URL}/client.js"

echo "------------------------------------------"

# 3. 后续清理工作
echo "-> 正在清理 LuCI 网页缓存..."
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

echo "-> 正在重载 Homeproxy 服务..."
/etc/init.d/homeproxy reload
if [ $? -eq 0 ]; then
    echo "   [成功] Homeproxy 服务已成功重载配置！"
else
    echo "   [警告] Homeproxy 服务重载可能失败，请检查服务状态。"
fi

echo "=========================================="
echo "更新流程结束！"
echo "=========================================="