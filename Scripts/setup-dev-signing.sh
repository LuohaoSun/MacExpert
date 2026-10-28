#!/bin/zsh
# 创建一张本机自签的代码签名证书，并导入 login keychain。
#
#   ./Scripts/setup-dev-signing.sh
#
# 用途：让 build.sh 用固定 identity（默认 "MacExpert Local Signing"）签名，
# 这样每次重编后 cdhash 不会变来变去，辅助功能授权不用反复点。
# 幂等：证书已经可用时直接退出，重复运行不会生成第二张。
#
# 只做用户域操作，不需要 sudo，也不会动系统钥匙串。
set -euo pipefail

IDENTITY="${MACEXPERT_SIGN_IDENTITY:-MacExpert Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 优先用系统自带的 LibreSSL：它导出的 PKCS#12 用 Security.framework 一定能读。
# Homebrew 的 OpenSSL 3 默认用 AES-256/PBKDF2 打包，老一点的安全框架会 import 失败。
OPENSSL="/usr/bin/openssl"
[[ -x "$OPENSSL" ]] || OPENSSL="$(command -v openssl)"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "❌ 找不到登录钥匙串: $KEYCHAIN" >&2
  echo "   请先在图形界面登录一次，并确认钥匙串访问里「登录」存在。" >&2
  exit 1
fi

# 先取成变量再匹配，避免 pipefail 下 grep -q 提前退出导致上游收到 SIGPIPE。
# 不用 -v：自签证书即使没设“始终信任”，也会出现在非 -v 列表里，
# 而且它已经足够让 codesign 正常签名（未信任只影响 Gatekeeper 的 spctl 评估）。
if grep -qF -- "\"$IDENTITY\"" <<< "$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null || true)"; then
  echo "✅ 已存在代码签名证书：$IDENTITY"
  echo "   直接运行 ./build.sh 就会用它签名，重编后辅助功能授权不会再失效。"
  echo "   （如果希望 Gatekeeper/spctl 也接受，可在「钥匙串访问」里把它的代码签名信任设为“始终信任”。）"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/macexpert-signing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_code_sign
prompt = no

[ dn ]
CN = $IDENTITY

[ v3_code_sign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

echo "== 1/4 生成自签证书（RSA 2048，10 年，codeSigning） =="
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -nodes \
  -keyout "$WORK/key.pem" \
  -out "$WORK/cert.pem" \
  -days 3650 \
  -config "$WORK/openssl.cnf"

PASS="$("$OPENSSL" rand -hex 16)"
echo "== 2/4 打包并导入 login keychain =="
"$OPENSSL" pkcs12 -export \
  -inkey "$WORK/key.pem" \
  -in "$WORK/cert.pem" \
  -name "$IDENTITY" \
  -out "$WORK/identity.p12" \
  -passout "pass:$PASS"

# -T /usr/bin/codesign：允许 codesign 使用这把私钥，避免每次签名都弹钥匙串授权。
security import "$WORK/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "== 3/4 设置用户域信任（可选，可能弹出系统授权窗口） =="
if security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" 2>/dev/null; then
  echo "✅ 已把「$IDENTITY」设为代码签名信任（用户域）"
  TRUSTED=1
else
  TRUSTED=0
  echo "⚠️ 自动设置信任失败/被取消。证书仍然可以直接用于本机签名，"
  echo "   只是 Gatekeeper 的 spctl 评估会拒绝（本机自用不需要过这一步）。"
  echo "   如果希望 spctl 也接受，请手动完成（不需要 sudo）："
  echo "   1. 打开「钥匙串访问」"
  echo "   2. 选择「登录」钥匙串 → 左侧「证书」→ 双击「$IDENTITY」"
  echo "   3. 展开「信任」→ 把「代码签名」改成「始终信任」"
  echo "   4. 关闭窗口，输入登录密码确认"
fi

echo "== 4/4 校验 =="
IDENTITIES="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null || true)"
if grep -qF -- "\"$IDENTITY\"" <<< "$IDENTITIES"; then
  echo "✅ find-identity 已能看到：$IDENTITY"
else
  echo "⚠️ 证书已导入，但 find-identity 仍未列出。"
  echo "   先完成上面的信任步骤，然后重新运行本脚本复查。"
fi

if (( TRUSTED )); then
  echo "== done =="
  echo "现在可以运行 ./build.sh（dev/release 都会优先使用这张证书）。"
else
  echo "== 证书已导入并可用于本机签名 =="
  echo "现在可以运行 ./build.sh；如果之后想分发给别人并过 Gatekeeper，"
  echo "再按上面的步骤把代码签名信任设为“始终信任”。"
fi
