#!/bin/bash

# =========================================================
# 1. 安装和更新软件包函数
# =========================================================
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "
	# 深度删除本地可能存在的重复软件包，彻底解决冲突
	for NAME in "${PKG_LIST[@]}"; do
		echo "正在检索并清理重复源码: $NAME"
		local FOUND_DIRS=$(find ../feeds/ -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "已删除冲突目录: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "未发现重复目录: $NAME"
		fi
	done

	# 【修正点：确保变量引用符号 $ 存在】
	local REPO_URL="github.com{PKG_REPO}.git"
	echo "正在克隆: $REPO_URL"
	
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "$REPO_URL" "$REPO_NAME"
	
	if [ $? -ne 0 ]; then
		echo "错误: 克隆 $PKG_NAME 失败"
		return 1
	fi

	# 处理克隆后的目录逻辑
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME/" -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		rm -rf "$PKG_NAME"
		mv -f "$REPO_NAME" "$PKG_NAME"
	else
		[ -d "$PKG_NAME" ] && rm -rf "$PKG_NAME"
		echo "插件 $PKG_NAME 已部署在 ./$REPO_NAME"
	fi
}

# =========================================================
# 2. 插件列表 (保持不变)
# =========================================================
UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master" "name"
UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master" "name"
UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master" "name"
UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master" "name"
UPDATE_PACKAGE "usteer" "leodereve/usteer" "master" "" "luci-app-usteer"
UPDATE_PACKAGE "luci-app-athena-led" "NONGFAH/luci-app-athena-led" "main" "name"
UPDATE_PACKAGE "luci-app-pushbot" "MasterOfStar/luci-app-pushbot" "master" "name"
UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main" "name"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main" "name"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main" "name"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "xiaorouji/openwrt-passwall2" "main" "pkg"
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main" "name"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main" "name"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master" "name"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main" "name"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main" "name"
UPDATE_PACKAGE "gecoosac" "lwb1978/openwrt-gecoosac" "main" "name"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "name"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/luci-app-netspeedtest" "master" "" "homebox speedtest"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main" "name"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main" "name"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main" "name"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main" "name"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main" "name"

# =========================================================
# 3. 更新版本函数 (确保 API 路径变量引用正确)
# =========================================================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/ -maxdepth 4 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)

	[ -z "$PKG_FILES" ] && return

	for PKG_FILE in $PKG_FILES; do
		local REPO_PATH=$(grep -Po "PKG_SOURCE_URL:=github.com\K[^/ ]+/[^/ ]+(?=\.git|/| )" "$PKG_FILE" | head -n 1)
		[ -z "$REPO_PATH" ] && continue

		# 【修正：确保 API 完整地址和变量符号】
		local API_URL="api.github.com{REPO_PATH}/releases"
		local PKG_TAG=$(curl -sL "$API_URL" | jq -r "if type==\"array\" then map(select(.prerelease == $PKG_MARK)) | first | .tag_name else empty end")

		[ -z "$PKG_TAG" ] || [ "$PKG_TAG" == "null" ] && continue

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
			local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
			local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
			local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
			local NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
			local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)
			
			if [ -n "$NEW_HASH" ]; then
				sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
				sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			fi
		fi
	done
}

UPDATE_VERSION "sing-box"

# 最后清理
for CONFLICT in jq wpad* hostapd* v2ray-geodata; do
    find ../feeds/ -type d -name "$CONFLICT" -prune -exec rm -rf {} \; 2>/dev/null
done

echo "Packages.sh 脚本执行完成。"
