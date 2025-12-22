#!/bin/bash

# =========================================================
# 1. 基础 UI 与 系统信息修改
# =========================================================
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

# =========================================================
# 2. Wi-Fi 默认设置
# =========================================================
WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
    sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
    sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

# =========================================================
# 3. 基础网络与主机名配置
# =========================================================
CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config

# 全局启用修复版 usteer (任何机型都会安装)
echo "CONFIG_PACKAGE_usteer=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config

if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# =========================================================
# 4. 高通平台 (QUALCOMMAX) 性能优化
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "正在执行高通平台 NSS 性能优化配置..."
    echo "CONFIG_FEED_nss_packages=n" >> ./.config
    echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
    
    if [[ ! "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* && ! "${WRT_CONFIG,,}" == *"aliyun_ap8220"* && ! "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
        echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
        echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
    fi

    echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
fi

# =========================================================
# 5. 特定机型逻辑 (插件注入、SQM 剔除、防火墙修改)
# =========================================================

# --- 5.1 插件注入 ---
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    echo "机型: 雅典娜 Main, 注入 PushBot, LED, Samba4, Conntrack..."
    echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
    echo "CONFIG_PACKAGE_curl=y" >> ./.config
    echo "CONFIG_PACKAGE_jsonfilter=y" >> ./.config
    
    # 注入 conntrack-tools (用于管理 iPad 外网访问)
    echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config

elif [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "机型: 雅典娜 (标准版), 注入 LED, Samba4..."
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
fi

# --- 5.2 剔除 SQM 与 防火墙放行 (针对 Dumb AP 机型) ---
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* || "${WRT_CONFIG,,}" == *"aliyun_ap8220"* || "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "正在为 $WRT_CONFIG 执行适配: 移除 SQM 并全开 WAN 防火墙..."
    
    sed -i '/luci-app-sqm/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-sqm is not set" >> ./.config
    sed -i '/sqm-scripts-nss/d' ./.config
    echo "# CONFIG_PACKAGE_sqm-scripts-nss is not set" >> ./.config
    
    mkdir -p ./package/base-files/files/etc/uci-defaults
    cat << 'EOF' > ./package/base-files/files/etc/uci-defaults/90-firewall-wan-accept
uci set firewall.@zone.input='ACCEPT'
uci set firewall.@zone.output='ACCEPT'
uci set firewall.@zone.forward='ACCEPT'
uci commit firewall
EOF
fi

# =========================================================
# 6. 全局主题强制切换为 Argon
# =========================================================
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config

# =========================================================
# 7. 强制开启 SSH 并修复
# =========================================================
SSH_CONF="./package/base-files/files/etc/config/dropbear"
if [ -f "$SSH_CONF" ]; then
    sed -i "s/option PasswordAuth.*/option PasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootPasswordAuth.*/option RootPasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootLogin.*/option RootLogin 'on'/g" $SSH_CONF
fi
mkdir -p ./package/base-files/files/etc/uci-defaults
cat << 'EOF' > ./package/base-files/files/etc/uci-defaults/99-ssh-fix
uci set dropbear.@dropbear.PasswordAuth='on'
uci set dropbear.@dropbear.RootPasswordAuth='on'
uci set dropbear.@dropbear.RootLogin='on'
uci commit dropbear
/etc/init.d/dropbear restart
EOF

# =========================================================
# 8. 修复哈希校验 (ath11k 与 自定义 usteer)
# =========================================================
# 修复 ath11k 固件校验
find ./package/ -wholename "*/ath11k-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +

# 修复自定义 usteer 源码校验 (防止编译因源码地址变动而报错)
find ./package/ -wholename "*/usteer/Makefile" -exec sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' {} +
