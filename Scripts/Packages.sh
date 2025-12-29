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
    # 仓库名：去掉前面的 "作者/"
    local REPO_NAME=${PKG_REPO#*/}

    echo " "
    # 深度删除本地可能存在的重复软件包，彻底解决 APK 冲突
    for NAME in "${PKG_LIST[@]}"; do
        echo "正在检索并清理重复源码: $NAME"
        local FOUND_DIRS
        FOUND_DIRS=$(find ../feeds/ -type d -iname "*$NAME*" 2>/dev/null)

        if [ -n "$FOUND_DIRS" ]; then
            while read -r DIR; do
                rm -rf "$DIR"
                echo "已删除冲突目录: $DIR"
            done <<< "$FOUND_DIRS"
        else
            echo "未发现重复目录: $NAME"
        fi
    done

    echo "正在克隆: $PKG_REPO"
    # 注意：这里一定要是 github.com/ + PKG_REPO
    git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"
    
    if [ $? -eq 0 ]; then
        echo "成功：$PKG_NAME 已下载。"
    else
        echo "失败：$PKG_NAME 无法下载，请检查日志。"
        return 1
    fi
    
    # 处理克隆后的仓库
    if [[ "$PKG_SPECIAL" == "pkg" ]]; then
        # openclash / passwall 这种多子目录仓库
        find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
        rm -rf "./$REPO_NAME/"
    elif [[ "$PKG_SPECIAL" == "name" ]]; then
        # 【修正部分】只有当仓库名和包名不同时，才执行重命名，防止 mv 报错
        if [ "$REPO_NAME" != "$PKG_NAME" ]; then
            [ -d "$PKG_NAME" ] && rm -rf "$PKG_NAME"
            mv -f "$REPO_NAME" "$PKG_NAME"
        fi
    fi
}

# =========================================================
# 2. 插件列表 (共 27 项)
# =========================================================
# =========================================================
# 2. 插件列表 (保持 27 项插件不变，严格对照原版写法修正)
# =========================================================
UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master"
UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master"
UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "usteer" "leodereve/usteer" "master" "" "luci-app-usteer"
UPDATE_PACKAGE "luci-app-athena-led" "NONGFAH/luci-app-athena-led" "main"
UPDATE_PACKAGE "luci-app-pushbot" "MasterOfStar/luci-app-pushbot" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "xiaorouji/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"
UPDATE_PACKAGE "gecoosac" "lwb1978/openwrt-gecoosac" "main"
# 修正：恢复 v2dat 提取，解决 v2ray-geoip 缺失问题
# --- 2025年 MosDNS v5 适配部分（体现作者 sbwml） ---

# 1. 替换 Golang 为 24.x（MosDNS 编译必需）
# 这里体现了作者 sbwml
rm -rf ../feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 24.x ../feeds/packages/lang/golang

# 2. 强力清理 ImmortalWrt 自带的旧版插件索引，防止冲突
find ../feeds/ -name "*v2ray-geodata*" | xargs rm -rf
find ../feeds/ -name "*mosdns*" | xargs rm -rf

# 3. 克隆插件源码（URL中明确体现作者 sbwml）
rm -rf v2ray-geodata mosdns
git clone --depth=1 https://github.com/sbwml/v2ray-geodata v2ray-geodata
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns mosdns

# 4. 强制刷新索引（解决 v2ray-geoip 不存在的问题）
cd ..
./scripts/feeds install -f v2ray-geodata
./scripts/feeds install -f mosdns
cd package/
#UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
#UPDATE_PACKAGE "v2ray-geodata" "sbwml/v2ray-geodata" "master"
# 修正：恢复多组件提取逻辑
UPDATE_PACKAGE "netspeedtest" "sirpdboy/luci-app-netspeedtest" "master" "" "homebox speedtest"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
# 修正：恢复 qt6 等依赖提取
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
# 修正：恢复 wolplus 等依赖提取
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

# =========================================================
# 3. 更新版本函数 (针对 sing-box)
# =========================================================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./ ../feeds/ -maxdepth 4 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		return
	fi

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO_PATH
		PKG_REPO_PATH=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com\K[^/ ]+/[^/ ]+(?=\.git|/| )" "$PKG_FILE" | head -n 1)
		[ -z "$PKG_REPO_PATH" ] && continue
		
		# 修正：api.github.com 后面补上 /repos/
		local API_URL="https://api.github.com/repos/$PKG_REPO_PATH/releases"
		local PKG_TAG
		PKG_TAG=$(curl -sL "$API_URL" | jq -r "if type==\"array\" then map(select(.prerelease == $PKG_MARK)) | first | .tag_name else empty end")
		
		if [[ -z "$PKG_TAG" || "$PKG_TAG" == "null" ]]; then
			continue
		fi

		local OLD_VER
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		
		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
			local OLD_URL
			OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
			local OLD_FILE
			OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
			local PKG_URL
			if [[ "$OLD_URL" == *"releases"* ]]; then
				PKG_URL="${OLD_URL%/}/$OLD_FILE"
			else
				PKG_URL="${OLD_URL%/}"
			fi
			local NEW_URL
			NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
			local NEW_HASH
			NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)
			
			if [ -n "$NEW_HASH" ]; then
				sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
				sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
				echo "$PKG_NAME 已更新至 $NEW_VER"
			fi
		fi
	done
}

UPDATE_VERSION "sing-box"

# =========================================================
# 4. 强制解决冲突
# =========================================================
echo "执行最后阶段的冲突清理..."
find ../feeds/ -type d -name "jq" -prune -exec rm -rf {} \;
find ../feeds/ -type d -name "wpad*" -prune -exec rm -rf {} \;
find ../feeds/ -type d -name "hostapd*" -prune -exec rm -rf {} \;
find ../feeds/ -type d -name "v2ray-geodata" -prune -exec rm -rf {} \;

echo "Packages.sh 执行完成。"
