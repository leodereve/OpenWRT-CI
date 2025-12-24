#!/bin/bash

# =========================================================
# 0. 变量初始化与固件标识
# =========================================================
# 识别是否为京东云雅典娜主路由模式
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
    WRT_MARK="Main"
else
    WRT_MARK="AP"
fi

# 写入固件内部版本显示信息
echo "CONFIG_IMAGEOPT=y" >> ./.config
echo "CONFIG_VERSION_DIST=\"$WRT_MARK\"" >> ./.config

# =========================================================
# 1. 系统与 UI 基础修改
# =========================================================
# 移除自动升级功能 (防止小白误点导致固件损坏)
find ./feeds/luci/collections/ -type f -name "Makefile" | xargs sed -i "/attendedsysupgrade/d"

# 强制注入 IP 地址到系统前端显示脚本
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" | xargs sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g"

# 状态栏显示标识: "版本号 / Main-日期"
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

# 基础 Luci 组件
sed -i '/CONFIG_PACKAGE_luci=y/d' ./.config
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config

# =========================================================
# 4. 插件分配逻辑 (X86 vs 嵌入式)
# =========================================================
if [[ "${WRT_CONFIG^^}" == *"X86"* ]]; then
    echo "检测到 X86 环境，配置科学上网与 DNS 方案..."
    # 禁用无用的漫游组件
    sed -i '/CONFIG_PACKAGE_luci-app-usteer/d' ./.config
    echo "# CONFIG_PACKAGE_luci-app-usteer is not set" >> ./.config
    
    # 启用 WolPlus 替代旧版 Wol
    sed -i '/CONFIG_PACKAGE_luci-app-wol/d' ./.config
    echo "CONFIG_PACKAGE_luci-app-wolplus=y" >> ./.config
    
    # DNS 与 代理插件
    echo "CONFIG_PACKAGE_mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-nikki=y" >> ./.config
else
    # 移动端/嵌入式 开启漫游辅助
    echo "非 X86 机型，启用默认漫游组件 (Usteer)..."
    echo "CONFIG_PACKAGE_luci-app-usteer=y" >> ./.config
fi

# =========================================================
# 5. 高通 (QUALCOMMAX) 与 雅典娜特定优化
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    # 基础 NSS 配置清理
    sed -i '/CONFIG_FEED_nss_packages/d' ./.config
    sed -i '/CONFIG_FEED_sqm_scripts_nss/d' ./.config
    
    # 针对雅典娜 Main 或 普通高通路由开启 NSS SQM
    if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02_main"* ]]; then
        echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
        echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
        echo "CONFIG_PACKAGE_conntrack-tools=y" >> ./.config
    fi

    # NSS 固件版本选型 (2025 推荐 IPQ50xx 用 12.2)
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
fi

# 雅典娜共有插件 (Main 和 AP 都需要的)
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "注入雅典娜专属驱动与 Samba4..."
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
fi

# =========================================================
# 6. Dumb AP 模式特殊处理 (针对非 Main 机型)
# =========================================================
# 判定条件：属于已知 AP 机型，或者是雅典娜但没有 _main 后缀
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* || "${WRT_CONFIG,,}" == *"aliyun_ap8220"* || ("${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* && "${WRT_CONFIG,,}" != *"_main"*) ]]; then
    echo "正在适配 Dumb AP 机型: 移除干扰插件并放开防火墙..."
    sed -i '/luci-app-sqm/d' ./.config
    sed -i '/luci-app-upnp/d' ./.config
    
    mkdir -p ./files/etc/uci-defaults
    cat << 'EOF' > ./files/etc/uci-defaults/99-dumb-ap-settings
#!/bin/sh
# 1. 开放 WAN 口防火墙以便从上级访问
for zone in $(uci show firewall | grep "=zone" | cut -d"." -f2 | cut -d"=" -f1); do
    if [ "$(uci -q get firewall.$zone.name)" = "wan" ]; then
        uci set firewall.$zone.input='ACCEPT'
        uci set firewall.$zone.forward='ACCEPT'
        uci set firewall.$zone.output='ACCEPT'
    fi
done
# 2. 禁用不必要的服务以节省内存
/etc/init.d/odhcpd disable
uci commit firewall
exit 0
EOF
    chmod +x ./files/etc/uci-defaults/99-dumb-ap-settings
fi

# =========================================================
# 7. 全局 UI 与 主题强制收尾
# =========================================================
# 强制移除默认主题并设置为 Argon
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
find ./feeds/luci/collections/ -type f -name "Makefile" | xargs sed -i "s/luci-theme-bootstrap/luci-theme-argon/g"
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config

# 注入自定义外部插件包
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" | sed 's/\bMain\b//g; s/\bAP\b//g' >> ./.config
fi

# =========================================================
# 8. 修复与安全增强
# =========================================================
# 强制 SSH 密码登录
mkdir -p ./files/etc/config
cat << 'EOF' > ./files/etc/config/dropbear
config dropbear
	option PasswordAuth 'on'
	option RootPasswordAuth 'on'
	option RootLogin 'on'
	option Port '22'
	option Interface 'lan'
	option enable '1'
EOF

# 跳过部分容易过期的哈希校验 (ath11k 固件/usteer)
find ./package/ -wholename "*/ath11k-firmware/Makefile" | xargs sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' 2>/dev/null
find ./package/ -wholename "*/usteer/Makefile" | xargs sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' 2>/dev/null

echo "Settings.sh 修改完成."
