#!/bin/bash

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#开启sqm-nss插件
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
	else
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	fi
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

##特别注意，这个可能时对所有都交换了
# ...（前半部分移除sysupgrade、修改IP、WIFI等保持不變）...

# =========================================================
# 網口交換邏輯：僅針對雅典娜 (athena) 和 Cudy TR3000 (tr3000)
# =========================================================
NETWORK_FILE="./package/base-files/files/etc/board.d/99-default_network"
CFG_GEN="./package/base-files/files/bin/config_generate"

# 定義路徑（確保變數在判斷前已定義）
NETWORK_FILE="./package/base-files/files/etc/board.d/99-default_network"
CFG_GEN="./package/base-files/files/bin/config_generate"

# 判斷當前編譯機型 (利用環境變數 $WRT_CONFIG)
# jdcloud_re-cs-02 = 雅典娜
# cudy_tr3000-v1 = Cudy TR3000 v1
if [[ "${WRT_CONFIG,,}" == *"IPQ60XX-WIFI-YES"* ]] || [[ "${WRT_CONFIG,,}" == *"cudy_tr3000-v1"* ]]; then
    echo "檢測到目標機型 $WRT_CONFIG，執行 2.5G 網口交換為 LAN..."
    
    # 1. 修改 99-default_network (影響首次啟動的邏輯)
    if [ -f "$NETWORK_FILE" ]; then
        sed -i "s/ucidef_set_interface_lan 'eth0'/ucidef_set_interface_lan 'eth1'/g" $NETWORK_FILE
        sed -i "s/ucidef_set_interface_wan 'eth1'/ucidef_set_interface_wan 'eth0'/g" $NETWORK_FILE
        echo "99-default_network 修改完成"
    fi

    # 2. 修改 config_generate (防止初始化時被二次覆蓋)
    if [ -f "$CFG_GEN" ]; then
        # 使用暫存替換，確保 eth0 和 eth1 互換不衝突
        sed -i "s/device='eth0'/device='temp_eth0'/g" $CFG_GEN
        sed -i "s/device='eth1'/device='eth0'/g" $CFG_GEN
        sed -i "s/device='temp_eth0'/device='eth1'/g" $CFG_GEN
        echo "config_generate 修改完成"
    fi
else
    echo "當前機型為 $WRT_CONFIG，不屬於雅典娜或 TR3000，跳過網口交換。"
fi

# =========================================================
# 主題更換邏輯：更換為 Argon
# =========================================================
echo "正在配置主題為 Argon..."

# 1. 確保原始的默認主題替換為 argon (針對 collections)
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" {} +
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-aurora/luci-theme-argon/g" {} +

# 2. 修改 .config 強制選中 argon 並取消 aurora
# 先刪除所有與主題相關的現有配置，防止衝突
sed -i '/CONFIG_PACKAGE_luci-theme-/d' ./.config
sed -i '/CONFIG_PACKAGE_luci-app-argon-config/d' ./.config

echo "CONFIG_PACKAGE_luci-theme-argon=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-argon-config=y" >> ./.config
# 明確禁用 aurora
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config
# 明確禁用 bootstrap (如果你不想保留備用)
echo "# CONFIG_PACKAGE_luci-theme-bootstrap is not set" >> ./.config

echo "主題更換配置完成。"
