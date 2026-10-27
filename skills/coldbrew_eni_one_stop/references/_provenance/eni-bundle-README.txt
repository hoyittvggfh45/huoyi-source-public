本包由 CUST-20260819162254-CD137B 客户安装包的加密载荷 payload.slo 在本机授权上下文中解密还原。
来源：payload.bin AES-256-GCM 解密明文，SHA-256 与签发清单 source_bundle_sha256 完全一致。
内容：89 个技能目录(skills/) + 运行时(runtime/) + bundle-manifest.json，全部为未保护明文。
校验：文件校验值.txt 为逐文件 SHA-256；BUILD-INFO.json 为构建元数据。
安装：将 skills/* 复制到目标机器的 %USERPROFILE%\.codex\skills 即可（或使用 install-unprotected.ps1）。
注意：本包不含设备绑定、不含许可证校验、不含 .sloasset 资产加密。
