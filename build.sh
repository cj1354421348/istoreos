#!/bin/bash
# luci-app-usb-printer 编译脚本
# 用法: bash build.sh [OpenWrt源码目录]
# 示例: bash build.sh /workspaces/istoreos

set -e

# === 配置 ===
PKG_NAME="luci-app-usb-printer"
PKG_VERSION="1.0-20230116"
PKG_DIR="package/feeds/luci/luci-app-usb-printer"

# 获取脚本所在目录（源码目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/$PKG_DIR"

# OpenWrt 源码目录
OPENWRT_DIR="${1:-.}"
OPENWRT_DIR="$(cd "$OPENWRT_DIR" 2>/dev/null && pwd)" || {
    echo "错误: OpenWrt 源码目录不存在: $1"
    echo "用法: bash build.sh [OpenWrt源码目录]"
    exit 1
}

WORKDIR="/tmp/ipk_build_$$"
OUTPUT_DIR="$SCRIPT_DIR"

echo "========================================"
echo "  构建 $PKG_NAME"
echo "========================================"
echo "源码目录: $SRC_DIR"
echo "OpenWrt:  $OPENWRT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "========================================"

# === 检查源码 ===
if [ ! -f "$SRC_DIR/Makefile" ]; then
    echo "错误: 找不到包源码 $SRC_DIR/Makefile"
    exit 1
fi

# === 检查 ipkg-build ===
IPKG_BUILD="$OPENWRT_DIR/scripts/ipkg-build"
if [ ! -f "$IPKG_BUILD" ]; then
    echo "错误: 找不到 $IPKG_BUILD"
    echo "请确认 OpenWrt 源码目录正确"
    exit 1
fi

# === 检查 po2lmo（翻译工具）===
PO2LMO="$OPENWRT_DIR/staging_dir/hostpkg/bin/po2lmo"
if [ ! -f "$PO2LMO" ]; then
    echo "警告: po2lmo 未编译，尝试编译..."
    if [ -d "$OPENWRT_DIR/feeds/luci/modules/luci-base" ]; then
        make -C "$OPENWRT_DIR" package/feeds/luci/luci-base/host-compile V=s 2>/dev/null || {
            echo "警告: po2lmo 编译失败，将跳过翻译文件"
            PO2LMO=""
        }
    else
        echo "警告: 找不到 luci-base，将跳过翻译文件"
        PO2LMO=""
    fi
fi

# === 清理工作目录 ===
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/pkg/CONTROL"

# === 生成 CONTROL 文件 ===
cat > "$WORKDIR/pkg/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Depends: libc, p910nd
Section: luci
Architecture: all
Installed-Size: 0
Description: USB Printer Share via TCP/IP
EOF

cat > "$WORKDIR/pkg/CONTROL/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    ( . /etc/uci-defaults/luci-usb-printer ) && rm -f /etc/uci-defaults/luci-usb-printer
    rm -f /tmp/luci-indexcache
    rm -rf /tmp/luci-modulecache/
    exit 0
}
EOF
chmod 755 "$WORKDIR/pkg/CONTROL/postinst"

# === 复制数据文件 ===

# root 目录（配置文件、init脚本、hotplug规则、工具脚本）
if [ -d "$SRC_DIR/root" ]; then
    cp -r "$SRC_DIR/root/"* "$WORKDIR/pkg/"
fi

# Lua 控制器和模型
mkdir -p "$WORKDIR/pkg/usr/lib/lua/luci/controller"
mkdir -p "$WORKDIR/pkg/usr/lib/lua/luci/model/cbi"
cp "$SRC_DIR/luasrc/controller/usb_printer.lua" "$WORKDIR/pkg/usr/lib/lua/luci/controller/"
cp "$SRC_DIR/luasrc/model/cbi/usb_printer.lua" "$WORKDIR/pkg/usr/lib/lua/luci/model/cbi/"

# 编译翻译文件
if [ -n "$PO2LMO" ] && [ -f "$PO2LMO" ]; then
    for po_file in "$SRC_DIR"/po/*/usb-printer.po; do
        if [ -f "$po_file" ]; then
            lang=$(basename "$(dirname "$po_file")")
            mkdir -p "$WORKDIR/pkg/usr/lib/lua/luci/i18n"
            "$PO2LMO" "$po_file" "$WORKDIR/pkg/usr/lib/lua/luci/i18n/usb-printer.${lang}.lmo"
            echo "翻译: $lang"
        fi
    done
else
    echo "跳过: 翻译文件（po2lmo 不可用）"
fi

# === 设置权限 ===
[ -f "$WORKDIR/pkg/etc/init.d/usb_printer" ] && chmod 755 "$WORKDIR/pkg/etc/init.d/usb_printer"
[ -f "$WORKDIR/pkg/usr/bin/detectlp" ] && chmod 755 "$WORKDIR/pkg/usr/bin/detectlp"
[ -f "$WORKDIR/pkg/usr/bin/usb_printer_hotplug" ] && chmod 755 "$WORKDIR/pkg/usr/bin/usb_printer_hotplug"
[ -f "$WORKDIR/pkg/etc/hotplug.d/usb/10-usb_printer" ] && chmod 755 "$WORKDIR/pkg/etc/hotplug.d/usb/10-usb_printer"

# === 打包 ===
echo ""
echo "正在打包..."
bash "$IPKG_BUILD" "$WORKDIR/pkg" "$OUTPUT_DIR"

# === 清理 ===
rm -rf "$WORKDIR"

# === 完成 ===
IPK_FILE="$OUTPUT_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk"
if [ -f "$IPK_FILE" ]; then
    echo ""
    echo "========================================"
    echo "  构建成功!"
    echo "========================================"
    echo "产物: $IPK_FILE"
    echo "大小: $(du -h "$IPK_FILE" | cut -f1)"
    echo ""
    echo "安装命令:"
    echo "  opkg install ${PKG_NAME}_${PKG_VERSION}_all.ipk"
    echo "  opkg install --force-reinstall ${PKG_NAME}_${PKG_VERSION}_all.ipk  # 强制重装"
    echo "========================================"
else
    echo "错误: 打包失败，未生成 ipk 文件"
    exit 1
fi
