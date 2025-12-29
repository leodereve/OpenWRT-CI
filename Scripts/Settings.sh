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
# 4. 插件分配与旁路由优化
# =========================================================

if [[ "${WRT_CONFIG^^}" == *"X86"* ]]; then
    echo "执行 X86 专项优化 (旁路由模式)..."

    # 1. 彻底移除无线相关软件包（解决 hostapd/wpad 编译报错）
    # 旁路由无 Wi-Fi 硬件，直接删除所有 wpad 和 hostapd 配置
    sed -i '/CONFIG_PACKAGE_wpad/d' ./.config
    sed -i '/CONFIG_PACKAGE_hostapd/d' ./.config
    echo "# CONFIG_PACKAGE_wpad-mesh-openssl is not set" >> ./.config
    echo "# CONFIG_PACKAGE_hostapd-common is not set" >> ./.config

    # 2. 移除无线漫游及相关插件
    sed -i '/CONFIG_PACKAGE_luci-app-usteer/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-usteer is not set" >> ./.config
    
    # 3. 移除 LED 设置菜单 (x86 环境通常不需要，防止报错)
    sed -i '/CONFIG_PACKAGE_luci-app-ledtrig-rssi/d' ./.config
    sed -i '/CONFIG_PACKAGE_luci-app-ledtrig-usbdev/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-led-control is not set" >> ./.config
    
        # 4. 核心插件分配 (修复 2025 年新版依赖冲突)
    sed -i '/CONFIG_PACKAGE_luci-app-wol/d' ./.config
    echo "CONFIG_PACKAGE_luci-app-wolplus=y" >> ./.config
    
    # 启用 MosDNS
    echo "CONFIG_PACKAGE_mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> ./.config
    
    # 启用 Nikki 并强制关闭可能冲突的 GeoData 包，让插件内部逻辑自行处理
    echo "CONFIG_PACKAGE_luci-app-nikki=y" >> ./.config
    
    # [关键修复] 解决 v2ray-geodata 冲突：强制不选由 MosDNS 额外拉起的冲突包
    echo "# CONFIG_PACKAGE_v2ray-geoip is not set" >> ./.config
    echo "# CONFIG_PACKAGE_v2ray-geosite is not set" >> ./.config
    
    # [关键修复] 解决 nikki 自身重叠冲突
    # 报错显示 nikki 冲突 nikki，通常是选了不同版本的 binary
    sed -i '/CONFIG_PACKAGE_nikki/d' ./.config
    echo "CONFIG_PACKAGE_nikki=y" >> ./.config
    
else
    # 物理路由/AP 平台逻辑
    echo "执行 物理路由/AP 平台配置..."
    # 强制锁定 wpad-mesh-openssl 以支持 802.11k/v/r
    sed -i '/CONFIG_PACKAGE_wpad/d' ./.config
    sed -i '/CONFIG_PACKAGE_hostapd/d' ./.config
    echo "CONFIG_PACKAGE_wpad-mesh-openssl=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config
fi

# =========================================================
# 5. 高通 (QUALCOMMAX) 专项修复与 AP 加速补完
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "执行 QUALCOMMAX 专项修复与加速补完..."
    
    # [修复] 跳过 NSS 固件哈希校验
    find ./feeds/nss_packages/ -wholename "*/nss-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
    find ./feeds/nss_packages/ -name "Makefile" | xargs sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' 2>/dev/null || true
    
    # [补完] NSS 桥接管理加速 (AP 模式核心)
    echo "CONFIG_PACKAGE_kmod-qca-nss-drv-bridge-mgr=y" >> ./.config
    echo "CONFIG_PACKAGE_iperf3=y" >> ./.config

    # NSS 固件版本选型
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
fi

# =========================================================
# 5.1 联发科 (FILOGIC/MEDIATEK) 专项优化
# =========================================================
if [[ "${WRT_TARGET^^}" == *"FILOGIC"* || "${WRT_TARGET^^}" == *"MEDIATEK"* ]]; then
    echo "执行 FILOGIC/MTK 专项硬件加速优化..."
    echo "CONFIG_PACKAGE_kmod-mt798x-hwnat=y" >> ./.config
fi

# 雅典娜特定逻辑
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    
    if [[ "${WRT_CONFIG,,}" == *"_main"* ]]; then
        echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
        echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
		# [修改点] 确保 pushbot 被选中，但清理其可能引发的重复依赖
        sed -i '/CONFIG_PACKAGE_luci-app-pushbot/d' ./.config
        echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
        echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config
        echo "CONFIG_PACKAGE_conntrack=y" >> ./.config
    fi
fi

# =========================================================
# 6. 移除无效依赖 (防止编译中断)
# =========================================================
sed -i '/CONFIG_PACKAGE_onionshare-cli/d' ./.config
sed -i '/CONFIG_PACKAGE_qmodem/d' ./.config
sed -i '/CONFIG_PACKAGE_asterisk/d' ./.config
sed -i '/CONFIG_PACKAGE_v2ray-geodata/d' ./.config
# [修复] 解决 2025 年新版 APK 管理器下的 jq 冲突
#sed -i '/CONFIG_PACKAGE_jq/d' ./.config
#echo "CONFIG_PACKAGE_jq=y" >> ./.config

# =========================================================
# 7. Dumb AP 模式处理 (防火墙 ACCEPT)
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
# 8. 全局收尾 (主题与 SSH)
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

# 修复哈希问题
find ./package/ -wholename "*/ath11k-firmware/Makefile" | xargs sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' 2>/dev/null
find ./package/ -wholename "*/usteer/Makefile" | xargs sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' 2>/dev/null

echo "Settings.sh 优化完成."
