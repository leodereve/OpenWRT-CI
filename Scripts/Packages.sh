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

	# 【修正】补全协议和变量符号 $
	local REPO_URL="github.com{PKG_REPO}.git"
	echo "正在克隆: $REPO_URL"
	
	# 克隆到以仓库名为名字的临时目录
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "$REPO_URL" "$REPO_NAME"
	
	if [ $? -ne 0 ]; then
		echo "错误: 克隆 $PKG_NAME 失败"
		return 1
	fi

	# 处理克隆后的目录逻辑
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 针对大仓库中提取特定子文件夹
		find "./$REPO_NAME/" -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		# 重命名整个仓库
		rm -rf "$PKG_NAME"
		mv -f "$REPO_NAME" "$PKG_NAME"
	else
		# 默认处理：如果已存在同名目录则覆盖
		[ -d "$PKG_NAME" ] && rm -rf "$PKG_NAME"
		# 如果仓库名和包名不同，且没有特殊指定，保持仓库名即可被 OpenWrt 识别
		echo "插件 $PKG_NAME 已部署在 ./$REPO_NAME"
	fi
}

# =========================================================
# 2. 主题插件 (针对 APK 编译器，推荐使用 name 参数确保路径唯一)
# =========================================================
UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master" "name"
UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master" "name"
UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master" "name"
UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master" "name"

# =========================================================
# 3. 无线漫游优化
# =========================================================
UPDATE_PACKAGE "usteer" "leodereve/usteer" "master" "" "luci-app-usteer"

# =========================================================
# 4. 常用功能与通用插件
# =========================================================
UPDATE_PACKAGE "luci-app-athena-led" "NONGFAH/luci-app-athena-led" "main" "name"
UPDATE_PACKAGE "luci-app-pushbot" "MasterOfStar/luci-app-pushbot" "master" "name"

# 代理与科学上网
UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main" "name"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main" "name"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main" "name"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "xiaorouji/openwrt-passwall2" "main" "pkg"

# 网络工具
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
# 5. 更新软件包版本函数
# =========================================================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	# 搜索当前目录下和 feeds 目录下的 Makefile
	local PKG_FILES=$(find ./ ../feeds/ -maxdepth 4 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME Makefile not found!"
		return
	fi

	echo -e "\n正在检查 $PKG_NAME 版本更新..."

	for PKG_FILE in $PKG_FILES; do
		# 【修正】更稳健的 Repo 地址提取逻辑
		local REPO_PATH=$(grep -Po "PKG_SOURCE_URL:=github.com\K[^/ ]+/[^/ ]+(?=\.git|/| )" "$PKG_FILE" | head -n 1)
		[ -z "$REPO_PATH" ] && continue

		# 【修正】补全完整的 API 地址
		local API_URL="api.github.com{REPO_PATH}/releases"
		local PKG_TAG=$(curl -sL "$API_URL" | jq -r "if type==\"array\" then map(select(.prerelease == $PKG_MARK)) | first | .tag_name else empty end")

		if [[ -z "$PKG_TAG" || "$PKG_TAG" == "null" ]]; then
			echo "无法获取 $PKG_NAME 的远程版本号，跳过。"
			continue
		fi

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')

		# 版本比对
		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
			echo "更新 $PKG_NAME: $OLD_VER -> $NEW_VER"
			
			local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
			local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
			local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
			
			# 转换变量并下载计算哈希
			local NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
			local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)
			
			if [ -n "$NEW_HASH" ]; then
				sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
				sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
				echo "$PKG_NAME 已成功更新至 $NEW_VER"
			fi
		else
			echo "$PKG_NAME 已是最新版本 ($OLD_VER)"
		fi
	done
}

# 更新 sing-box 核心版本
UPDATE_VERSION "sing-box"

# =========================================================
# 6. 强制解决冲突 (针对常见构建错误项)
# =========================================================
echo "正在执行最后阶段的强制清理冲突项..."
for CONFLICT in jq wpad* hostapd* v2ray-geodata; do
    find ../feeds/ -type d -name "$CONFLICT" -prune -exec rm -rf {} \; 2>/dev/null
done

echo "Packages.sh 脚本执行完成。"
