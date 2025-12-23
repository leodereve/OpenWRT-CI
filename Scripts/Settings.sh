#!/bin/bash

# =========================================================
# 0. 固件标识符定义 (用于 Web UI 显示)
# =========================================================
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    WRT_MARK="Main"
else
    WRT_MARK="AP"
fi

# 注入内部编译配置，强制改变固件内版本信息
echo "CONFIG_IMAGEOPT=y" >> ./.config
echo "CONFIG_VERSION_DIST=\"$WRT_MARK\"" >> ./.config

# =========================================================
# 1. 基础 UI 与 系统信息修改
# =========================================================
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
# Web 界面状态栏显示：Main-日期 或 AP-日期
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

# =========================================================
# 核心插件按机型分配 (逻辑修正)
# =========================================================
if [[ "${WRT_CONFIG^^}" == *"X86"* ]]; then
    echo "检测到 X86 环境，执行特定插件配置 (Nikki/MosDNS/WolPlus)..."
    
    # 1. 彻底禁用 usteer (清理旧配置防止干扰)
    sed -i '/CONFIG_PACKAGE_usteer/d' ./.config
    sed -i '/CONFIG_PACKAGE_luci-app-usteer/d' ./.config
    echo "# CONFIG_PACKAGE_usteer is not set" >> ./.config
    echo "# CONFIG_PACKAGE_luci-app-usteer is not set" >> ./.config
    
    # 2. 启用核心插件 (清理旧的 wol 勾选，强制选中 wolplus)
    sed -i '/CONFIG_PACKAGE_luci-app-wol/d' ./.config
    echo "CONFIG_PACKAGE_luci-app-wolplus=y" >> ./.config
    echo "# CONFIG_PACKAGE_luci-app-wol is not set" >> ./.config

    echo "CONFIG_PACKAGE_mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_v2dat=y" >> ./.config

    echo "CONFIG_PACKAGE_nikki=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-nikki=y" >> ./.config
else
    # 非 X86 机型保持原有 Usteer 漫游开启
    echo "非 X86 机型，启用默认漫游组件 (Usteer)..."
    echo "CONFIG_PACKAGE_usteer=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config
fi

# 注入外部变量中的插件 (优先级最高，会覆盖前面的设置)
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" | sed 's/\bMain\b//g; s/\bAP\b//g' >> ./.config
fi

# =========================================================
# 4. 高通平台 (QUALCOMMAX) 性能优化
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "执行高通平台性能优化..."
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
# 5. 特定机型逻辑 (插件注入、Dumb AP 防火墙)
# =========================================================
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    echo "机型: 雅典娜 Main 插件注入..."
    echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
    echo "CONFIG_PACKAGE_curl=y" >> ./.config
    echo "CONFIG_PACKAGE_jsonfilter=y" >> ./.config
    echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
    echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
elif [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "机型: 雅典娜标准版 (AP) 插件注入 (包含 Samba4)..."
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
fi

# 5.2 针对 Dumb AP 机型移除 SQM 并全开 WAN 防火墙
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* || "${WRT_CONFIG,,}" == *"aliyun_ap8220"* || ("${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* && "${WRT_CONFIG,,}" != *"_main"*) ]]; then
    echo "正在适配 Dumb AP 机型: 移除 SQM 并全开 WAN 防火墙..."
    sed -i '/luci-app-sqm/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-sqm is not set" >> ./.config
    
    mkdir -p ./files/etc/uci-defaults
    cat << 'EOF' > ./files/etc/uci-defaults/90-firewall-wan-accept
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
    chmod +x ./files/etc/uci-defaults/90-firewall-wan-accept
fi

# =========================================================
# 6. 全局主题强制切换为 Argon
# =========================================================
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config

# =========================================================
# 7. 强制开启 SSH 并修复实例缺失
# =========================================================
mkdir -p ./files/etc/config
cat << 'EOF' > ./files/etc/config/dropbear
config dropbear
	option PasswordAuth 'on'
	option RootPasswordAuth 'on'
	option RootLogin 'on'
	option Port '22'
	option enable '1'
EOF

# =========================================================
# 8. 修复哈希校验与部分驱动问题
# =========================================================
find ./package/ -wholename "*/ath11k-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
find ./package/ -wholename "*/usteer/Makefile" -exec sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' {} +
