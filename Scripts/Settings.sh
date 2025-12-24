#!/bin/bash

# =========================================================
# 0. 变量初始化与固件标识
# =========================================================
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    WRT_MARK="Main"
else
    WRT_MARK="AP"
fi

echo "CONFIG_IMAGEOPT=y" >> ./.config
echo "CONFIG_VERSION_DIST=\"$WRT_MARK\"" >> ./.config

# =========================================================
# 1. 系统与 UI 基础修改
# =========================================================
find ./feeds/luci/collections/ -type f -name "Makefile" | xargs sed -i "/attendedsysupgrade/d"
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" | xargs sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g"
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" | xargs sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g"

# =========================================================
# 2. Wi-Fi 默认配置适配
# =========================================================
WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$WIFI_SH" ]; then
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
    sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
    sed -i "s/country='.*'/country='CN'/g" "$WIFI_UC"
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" "$WIFI_UC"
fi

# =========================================================
# 3. 基础网络与核心编译选项
# =========================================================
CFG_FILE="./package/base-files/files/bin/config_generate"
[ -f "$CFG_FILE" ] && {
    sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
    sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
}

echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config

# =========================================================
# 4. 插件分配逻辑
# =========================================================
if [[ "${WRT_CONFIG^^}" == *"X86"* ]]; then
    sed -i '/CONFIG_PACKAGE_luci-app-usteer/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-usteer is not set" >> ./.config
    sed -i '/CONFIG_PACKAGE_luci-app-wol/d' ./.config
    echo "CONFIG_PACKAGE_luci-app-wolplus=y" >> ./.config
    echo "CONFIG_PACKAGE_mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-nikki=y" >> ./.config
else
    echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config
fi

# =========================================================
# 5. 高通 (QUALCOMMAX) 修复与优化 (解决 NSS 下载报错)
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "执行 QUALCOMMAX 专项修复..."
    
    # [修复] 强制跳过 NSS 固件哈希校验 (解决 ERROR: nss-firmware failed to build)
    find ./feeds/nss_packages/ -wholename "*/nss-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
    find ./feeds/nss_packages/ -name "Makefile" | xargs sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' 2>/dev/null || true
    
    # [修复] 替换失效的 Qualcomm 下载域名为 GitCodelinaro 镜像
    find ./feeds/nss_packages/ -name "Makefile" | xargs sed -i 's/https:\/\/sources.openwrt.org\/.*qca-nss/https:\/\/git.codelinaro.org\/clo\/la\/platform\/vendor\/qcom-opensource\/wlan\/fw-api/-/archive\/main\/fw-api-main.tar.gz?path=qca-nss/g' 2>/dev/null || true

    # NSS 固件版本选型
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
fi

# 雅典娜特定逻辑
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
    
    if [[ "${WRT_CONFIG,,}" == *"_main"* ]]; then
        echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
        echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
        echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config
    fi
fi

# =========================================================
# 6. 移除断头依赖 (解决 WARNING 导致的编译中断)
# =========================================================
# 移除源码中存在但 feeds 缺失的导致报错的包
sed -i '/CONFIG_PACKAGE_onionshare-cli/d' ./.config
sed -i '/CONFIG_PACKAGE_qmodem/d' ./.config
sed -i '/CONFIG_PACKAGE_asterisk/d' ./.config

# =========================================================
# 7. Dumb AP 模式处理
# =========================================================
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* || "${WRT_CONFIG,,}" == *"aliyun_ap8220"* || ("${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* && "${WRT_CONFIG,,}" != *"_main"*) ]]; then
    sed -i '/luci-app-sqm/d' ./.config
    mkdir -p ./files/etc/uci-defaults
    cat << 'EOF' > ./files/etc/uci-defaults/99-dumb-ap-settings
#!/bin/sh
for zone in $(uci show firewall | grep "=zone" | cut -d"." -f2 | cut -d"=" -f1); do
    if [ "$(uci -q get firewall.$zone.name)" = "wan" ]; then
        uci set firewall.$zone.input='ACCEPT'
        uci set firewall.$zone.forward='ACCEPT'
        uci set firewall.$zone.output='ACCEPT'
    fi
done
uci commit firewall
exit 0
EOF
    chmod +x ./files/etc/uci-defaults/99-dumb-ap-settings
fi

# =========================================================
# 8. 全局收尾 (Argon 主题与 SSH)
# =========================================================
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
find ./feeds/luci/collections/ -type f -name "Makefile" | xargs sed -i "s/luci-theme-bootstrap/luci-theme-argon/g"
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config

if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" | sed 's/\bMain\b//g; s/\bAP\b//g' >> ./.config
fi

mkdir -p ./files/etc/config
cat << 'EOF' > ./files/etc/config/dropbear
config dropbear
	option PasswordAuth 'on'
	option RootPasswordAuth 'on'
	option RootLogin 'on'
	option Port '22'
	option enable '1'
EOF

# 修复其他哈希问题
find ./package/ -wholename "*/ath11k-firmware/Makefile" | xargs sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' 2>/dev/null
find ./package/ -wholename "*/usteer/Makefile" | xargs sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' 2>/dev/null

echo "Settings.sh 修复完成."
