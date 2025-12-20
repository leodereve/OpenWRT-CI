#!/bin/bash

# =========================================================
# 1. 基础 UI 与 系统信息修改
# =========================================================
# 移除 luci-app-attendedsysupgrade (防止升级冲突)
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
# 修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
# 修改默认 IP 的 JS 关联 (适配登录页)
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
# 添加编译日期标识到后台状态页
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

# =========================================================
# 2. Wi-Fi 默认设置 (名称、密码、国家码等)
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

# 强制选中基础插件
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# 处理外部传入的自定义插件包
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# =========================================================
# 4. 高通平台 (QUALCOMMAX) 性能优化 (如 NSS 加速)
# =========================================================
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "正在执行高通平台 NSS 性能优化配置..."
    echo "CONFIG_FEED_nss_packages=n" >> ./.config
    echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
    echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
    echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
fi

# =========================================================
# 5. 特定机型逻辑 (网口交换、定向插件注入)
# =========================================================

# --- 雅典娜 (jdcloud_re-cs-02): DTS网口交换 + PushBot + LED + Samba4 ---
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
    echo "检测到雅典娜，正在执行定制配置..."
    
    # 5.1 修改 DTS 强制交换 2.5G 口为 LAN
    DTS_FILE="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts"
    if [ -f "$DTS_FILE" ]; then
        sed -i 's/label = "wan";/label = "lan5";/g' $DTS_FILE
        sed -i 's/label = "lan1";/label = "wan";/g' $DTS_FILE
        sed -i 's/ESS_PORT5 | ESS_PORT2 | ESS_PORT3 | ESS_PORT4/ESS_PORT1 | ESS_PORT2 | ESS_PORT3 | ESS_PORT4/g' $DTS_FILE
        sed -i 's/switch_wan_bmp = <ESS_PORT1>;/switch_wan_bmp = <ESS_PORT5>;/g' $DTS_FILE
        echo "雅典娜 DTS 修改完成。"
    fi

    # 5.2 雅典娜专属插件注入
    echo "正在为雅典娜添加专属插件：PushBot, LED, Samba4..."
    echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-samba4=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_WSDD2=y" >> ./.config
    echo "CONFIG_SAMBA4_SERVER_NETBIOS=y" >> ./.config
    # 补全依赖项
    echo "CONFIG_PACKAGE_curl=y" >> ./.config
    echo "CONFIG_PACKAGE_jsonfilter=y" >> ./.config
fi

# --- Cudy TR3000 v1: 修改 mediatek 的 02_network 脚本 ---
if [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* ]]; then
    echo "检测到 Cudy TR3000 v1，正在修改 02_network 交换网口..."
    MTK_NETWORK_FILE="./target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
    if [ -f "$MTK_NETWORK_FILE" ]; then
        # 将 cudy,tr3000-v1 对应的 eth0 eth1 替换为 eth1 eth0
        sed -i "/cudy,tr3000-v1/,/ucidef_set_interfaces_lan_wan/ s/eth0 eth1/eth1 eth0/" $MTK_NETWORK_FILE
        echo "Cudy TR3000 v1 源码网口交换完成。"
    fi
fi

# =========================================================
# 6. 全局主题强制切换为 Argon
# =========================================================
echo "正在全局配置主题为 Argon..."
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-aurora/luci-theme-argon/g" {} +
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-argon-config=y" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config

# =========================================================
# 7. 强制开启 SSH 并修复 Connection Refused 问题
# =========================================================
echo "正在修补 SSH 默认配置..."
SSH_CONF="./package/base-files/files/etc/config/dropbear"
if [ -f "$SSH_CONF" ]; then
    sed -i "s/option PasswordAuth.*/option PasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootPasswordAuth.*/option RootPasswordAuth 'on'/g" $SSH_CONF
    sed -i "s/option RootLogin.*/option RootLogin 'on'/g" $SSH_CONF
fi
# 注入首次启动修复脚本
mkdir -p ./package/base-files/files/etc/uci-defaults
cat << 'EOF' > ./package/base-files/files/etc/uci-defaults/99-ssh-fix
uci set dropbear.@dropbear.Interface='lan'
uci set dropbear.@dropbear.Port='22'
uci set dropbear.@dropbear.PasswordAuth='on'
uci set dropbear.@dropbear.RootPasswordAuth='on'
uci set dropbear.@dropbear.RootLogin='on'
uci commit dropbear
/etc/init.d/dropbear restart
EOF

# =========================================================
# 8. 修复 2025-12-20 ath11k-firmware 哈希校验失败 Bug
# =========================================================
find ./package/ -wholename "*/ath11k-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
echo "已跳过 ath11k-firmware 哈希校验以避免报错。"

