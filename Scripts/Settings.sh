luci-light
luci-app-argon-config
luci-theme-argon

luci-app-aurora-config
luci-theme-aurora

https://github.com/leodereve/OpenWRT-CI/releases/download/IPQ60XX-WIFI-YES-leodereve-main-25.12.19-18.18.13/leodereve-main-qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-factory-25.12.19-18.18.13.bin


https://github.com/leodereve/OpenWRT-CI/releases/download/MEDIATEK-VIKINGYFY-owrt-25.12.19-16.05.13/VIKINGYFY-owrt-mediatek-filogic-cudy_tr3000-v1-squashfs-sysupgrade-25.12.19-16.05.13.bin

jdcloud_re-cs-02

cudy_tr3000-v1




#!/bin/bash

# 移除 luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
# 修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
# 修改 immortalwrt.lan 关联 IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
# 添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
    # 修改 WIFI 名称
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
    # 修改 WIFI 密码
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
    # 修改 WIFI 名称
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
    # 修改 WIFI 密码
    sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
    # 修改 WIFI 地区
    sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
    # 修改 WIFI 加密
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
# 修改默认 IP 地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
# 修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

# 基础配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# 手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# 高通平台调整
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
    # 取消 nss 相关 feed
    echo "CONFIG_FEED_nss_packages=n" >> ./.config
    echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
    # 开启 sqm-nss 插件
    echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
    echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
    # 设置 NSS 版本
    echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
    # 无 WIFI 配置调整 Q6 大小
    if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
        find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
        echo "qualcommax set up nowifi successfully!"
    fi
fi

# =========================================================
# 机型特定逻辑：网口交换 + 雅典娜专供 PushBot
# =========================================================
# jdcloud_re-cs-02 对应雅典娜
# cudy_tr3000-v1 对应 Cudy
if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]] || [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* ]]; then
    echo "检测到目标机型 $WRT_CONFIG，执行网口交换逻辑..."
    
    NETWORK_FILE="./package/base-files/files/etc/board.d/99-default_network"
    # 1. 修改 99-default_network
    if [ -f "$NETWORK_FILE" ]; then
        sed -i "s/ucidef_set_interface_lan 'eth0'/ucidef_set_interface_lan 'eth1'/g" $NETWORK_FILE
        sed -i "s/ucidef_set_interface_wan 'eth1'/ucidef_set_interface_wan 'eth0'/g" $NETWORK_FILE
        echo "99-default_network 修改完成"
    fi

    # 2. 修改 config_generate (CFG_FILE 已在上方定义)
    if [ -f "$CFG_FILE" ]; then
        sed -i "s/device='eth0'/device='temp_eth0'/g" $CFG_FILE
        sed -i "s/device='eth1'/device='eth0'/g" $CFG_FILE
        sed -i "s/device='temp_eth0'/device='eth1'/g" $CFG_FILE
        echo "config_generate 修改完成"
    fi

    # 3. 雅典娜专享插件 (仅限 jdcloud_re-cs-02)
    if [[ "${WRT_CONFIG,,}" == *"jdcloud_re-cs-02"* ]]; then
        echo "正在为雅典娜添加 PushBot 和 LED 屏幕驱动..."
        echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-athena-led=y" >> ./.config
    fi
else
    echo "当前机型为 $WRT_CONFIG，不执行网口交换。"
fi

# =========================================================
# 全局主题更换逻辑：更换为 Argon
# =========================================================
echo "正在配置主题为 Argon..."
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-aurora/luci-theme-argon/g" {} +

sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
sed -i '/CONFIG_PACKAGE_luci-app-argon-config/d' ./.config
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-argon-config=y" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-bootstrap is not set" >> ./.config

# =========================================================
# 修复 2025-12-20 源码引入的 ath11k-firmware 哈希校验失败 Bug
# =========================================================
find ./package/ -wholename "*/ath11k-firmware/Makefile" -exec sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' {} +
echo "已跳过 ath11k-firmware 的哈希校验以避免报错。"
