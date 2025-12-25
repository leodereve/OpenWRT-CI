#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

# =========================================================
# 1. 预置 HomeProxy 数据 (Surge 规则转换)
# =========================================================
# 增强了对目录的检测，并确保脚本在处理数据后能正确返回
if [ -d *"homeproxy"* ]; then
	echo "正在更新 HomeProxy 资源数据..."

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	# 彻底清理旧资源，防止版本冲突
	rm -rf ./$HP_PATH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "github.com" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver > /dev/null
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt 
	sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

	cd .. && rm -rf ./$HP_RULE/
	echo "HomeProxy 数据更新完成！版本: $RES_VER"
	cd $PKG_PATH
fi

# =========================================================
# 2. 修改 Argon 主题配置 (Bing 壁纸与配色)
# =========================================================
# 2025 年新版 Argon 的配置文件键名有所变动，此处进行了修正
if [ -d *"luci-theme-argon"* ]; then
    echo "正在修复制 Argon 主题默认配置..."
    ARGON_CFG=$(find . -wholename "*/luci-theme-argon/root/etc/config/argon" 2>/dev/null)
    if [ -n "$ARGON_CFG" ]; then
        # 修改主题色为 #31a1a1，透明度 0.5，开启 Bing 壁纸
        sed -i "s/primary '.*'/primary '#31a1a1'/" "$ARGON_CFG"
        sed -i "s/transparency '.*'/transparency '0.5'/" "$ARGON_CFG"
        # 修正：新版开启 Bing 背景的键通常是 bing_background
        sed -i "s/bing_background '.*'/bing_background '1'/" "$ARGON_CFG"
        echo "Argon 主题配色与 Bing 壁纸配置已更新！"
    fi
    cd $PKG_PATH
fi

# =========================================================
# 3. 高通 NSS 驱动启动顺序修复 (针对 IPQ 平台)
# =========================================================
NSS_DRV=$(find ../feeds/nss_packages/ -name "qca-nss-drv.init" 2>/dev/null)
if [ -f "$NSS_DRV" ]; then
	sed -i 's/START=.*/START=85/g' "$NSS_DRV"
	echo "已修正 qca-nss-drv 启动顺序为 85。"
fi

NSS_PBUF=$(find ./ -name "qca-nss-pbuf.init" 2>/dev/null)
if [ -f "$NSS_PBUF" ]; then
	sed -i 's/START=.*/START=86/g' "$NSS_PBUF"
	echo "已修正 qca-nss-pbuf 启动顺序为 86。"
fi

# =========================================================
# 4. 修复常用包编译问题 (Tailscale, Rust, DiskMan)
# =========================================================
# 修复 Tailscale 配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile" 2>/dev/null)
if [ -f "$TS_FILE" ]; then
	sed -i '/\/files/d' "$TS_FILE"
	echo "Tailscale 冲突已修复。"
fi

# 修复 Rust 编译失败 (针对内存不足环境，跳过 CI-LLVM)
RUST_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile" 2>/dev/null)
if [ -f "$RUST_FILE" ]; then
	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
	echo "Rust 编译配置已修正。"
fi

# 修复 DiskMan 依赖 (使用内核原生 ntfs3 驱动)
DM_FILE=$(find ./ -name "Makefile" | grep "luci-app-diskman")
if [ -f "$DM_FILE" ]; then
	sed -i 's/fs-ntfs/fs-ntfs3/g' "$DM_FILE"
	sed -i '/ntfs-3g-utils /d' "$DM_FILE"
	echo "DiskMan 依赖已修正为 ntfs3。"
fi

# 修复 Netspeedtest 脚本残留
NST_DEFAULTS=$(find ./ -name "99_netspeedtest.defaults" 2>/dev/null)
if [ -f "$NST_DEFAULTS" ]; then
	sed -i '$a\exit 0' "$NST_DEFAULTS"
	echo "Netspeedtest 残留问题已修复。"
fi

cd $PKG_PATH
echo "handle.sh 所有修复逻辑执行完毕。"
