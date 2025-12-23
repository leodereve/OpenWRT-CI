#!/bin/bash

# =========================================================
# 1. 基礎 UI 與 系統資訊修改
# =========================================================
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

# =========================================================
# 2. Wi-Fi 默認設置
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
# 3. 基礎網絡與主機名配置
# =========================================================
CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config

# 全局啟用修復版 usteer (任何機型都會安裝)
echo "CONFIG_PACKAGE_usteer=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config

if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# =========================================================
# 4. 高通平台 (QUALCOMMAX) 性能優化
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "正在執行高通平台 NSS 性能優化配置..."
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
# 5. 特定機型邏輯 (插件注入、SQM 剔除、防火牆修改)
# =========================================================

# --- 5.1 插件注入 ---
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    echo "機型: 雅典娜 Main, 注入 PushBot, LED, Samba4, Conntrack..."
    echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
    echo "CONFIG_PACKAGE_curl=y" >> ./.config
    echo "CONFIG_PACKAGE_jsonfilter=y" >> ./.config
    echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config

elif [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "機型: 雅典娜 (標準版), 注入 LED, Samba4..."
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
fi

# --- 5.2 剔除 SQM 與 防火牆放行 (針對 Dumb AP 機型) ---
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* || "${WRT_CONFIG,,}" == *"aliyun_ap8220"* || "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "正在為 $WRT_CONFIG 執行適配: 移除 SQM 並全開 WAN 防火牆..."
    
    sed -i '/luci-app-sqm/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-sqm is not set" >> ./.config
    sed -i '/sqm-scripts-nss/d' ./.config
    echo "# CONFIG_PACKAGE_sqm-scripts-nss is not set" >> ./.config
    
    mkdir -p ./package/base-files/files/etc/uci-defaults
    cat << 'EOF' > ./package/base-files/files/etc/uci-defaults/90-firewall-wan-accept
#!/bin/sh
# 查找所有名為 'wan' 的區域並設置為 ACCEPT
zones=$(uci show firewall | grep "=zone" | cut -d'.' -f2 | cut -d'=' -f1)
for zone in $zones; do
    if [ "$(uci -q get firewall.$zone.name)" = "wan" ]; then
        uci set firewall.$zone.input='ACCEPT'
        uci set firewall.$zone.forward='ACCEPT'
        uci set firewall.$zone.output='ACCEPT'
    fi
done
uci commit firewall
exit 0
EOF
fi

# =========================================================
# 6. 全局主題強制切換為 Argon
# =========================================================
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config

# =========================================================
# 7. 強制開啟 SSH 並修復
# =========================================================
SSH_CONF="./package/base-files/files/etc/config/dropbear"
if [ -f "$SSH_CONF" ]; then
    sed -i "s/option PasswordAuth.*/option PasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootPasswordAuth.*/option RootPasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootLogin.*/option RootLogin 'on'/g" $SSH_CONF
fi
mkdir -p ./package/base-files/files/etc/uci-defaults
cat << 'EOF' > ./package/base-files/files/etc/uci-defaults/99-ssh-fix
#!/bin/sh
uci set dropbear.@dropbear[0].PasswordAuth='on'
uci set dropbear.@dropbear[0].RootPasswordAuth='on'
uci set dropbear.@dropbear[0].RootLogin='on'
uci commit dropbear
exit 0
EOF

# =========================================================
# 8. 修復哈希校驗 (ath11k 與 自定義 usteer)
# =========================================================
find ./package/ -wholename "*/ath11k-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
find ./package/ -wholename "*/usteer/Makefile" -exec sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' {} +
