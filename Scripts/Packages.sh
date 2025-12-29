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
	# 深度删除本地可能存在的重复软件包，彻底解决 APK 冲突
	for NAME in "${PKG_LIST[@]}"; do
		echo "正在检索并清理重复源码: $NAME"
		# 这里的 find 不再限制深度，确保彻底删除 feeds/packages/utils/ 等深层目录
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

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "github.com"
	
	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# =========================================================
# 2. 主题插件
# =========================================================
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"
UPDATE_PACKAGE "argon-config" "jerrykuku/luci-app-argon-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

# =========================================================
# 3. 无线漫游优化 (usteer 已包含原生和 luci 插件)
# =========================================================
UPDATE_PACKAGE "usteer" "leodereve/usteer" "master" "" "luci-app-usteer"

# =========================================================
# 4. 常用功能与通用插件
# =========================================================
# 京东云雅典娜专用
UPDATE_PACKAGE "athena-led" "NONGFAH/luci-app-athena-led" "main"
UPDATE_PACKAGE "luci-app-pushbot" "MasterOfStar/luci-app-pushbot" "master"

# 代理与科学上网
UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "xiaorouji/openwrt-passwall2" "main" "pkg"

# 网络工具
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"
UPDATE_PACKAGE "gecoosac" "lwb1978/openwrt-gecoosac" "main"
# 修改：移除显式的 v2dat 引入，sbwml 的仓库会自动处理依赖，防止 geodata 冲突
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/luci-app-netspeedtest" "master" "" "homebox speedtest"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

# =========================================================
# 5. 更新软件包版本函数
# =========================================================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/ -maxdepth 4 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		# 修改：修复了 API 路径缺失的斜杠
		local PKG_TAG=$(curl -sL "api.github.com" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")

		if [[ -z "$PKG_TAG" || "$PKG_TAG" == "null" ]]; then
			echo "Failed to fetch $PKG_NAME version, skipping."
			continue
		fi

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE updated to $NEW_VER"
		fi
	done
}

UPDATE_VERSION "sing-box"

# =========================================================
# 6. 强制解决冲突 (全平台通用编译最核心修改)
# =========================================================
echo "正在执行最后阶段的强制清理..."

# 解决 jq 重复定义冲突 (APK Manager 零容忍项)
find ../feeds/ -type d -name "jq" -prune -exec rm -rf {} \;

# 解决无线组件冲突
find ../feeds/ -type d -name "wpad*" -prune -exec rm -rf {} \;
find ../feeds/ -type d -name "hostapd*" -prune -exec rm -rf {} \;

# 解决 Geodata 提供者冲突 (针对 v2ray-geoip / v2ray-geosite)
find ../feeds/ -type d -name "v2ray-geodata" -prune -exec rm -rf {} \;

echo "Packages.sh 脚本执行完成。"
