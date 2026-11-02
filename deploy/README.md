# 本地开发包

在项目根目录运行 `./scripts/run.sh`，将构建并打开 `deploy/build/Forma.app`。

`./scripts/build.sh Release` 生成优化的 Apple Silicon 本地预览包；`./scripts/verify.sh` 运行测试并生成 Debug 集成检查产物。

开发包没有完成 Developer ID 签名和公证，不是对外发布包。正式发布需在受保护环境配置开发者身份、验证 Sandbox、签名归档、公证及 staple，仓库不得保存证书私钥。

应用内核版本 0.5.0，当前功能与限制见根目录 README 和 `docs/开发里程碑.md`。
