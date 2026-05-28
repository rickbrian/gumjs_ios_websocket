# GumJS iOS WebSocket

iOS 越狱插件：通过 WebSocket 向目标 App 注入 Frida GumJS 脚本，支持热更新。

基于 Android [zygisk-gumjs-websocket](https://github.com/yizhiyonggangdexiaojia/zygisk_gumjs_websocket) 项目移植。

## 架构

```
┌──────────────┐   WebSocket    ┌─────────────────────────┐
│  PC 端       │ ◄────────────► │  iOS 设备（越狱）        │
│  server.py   │  JS 脚本/日志   │  目标 App 进程           │
│  (端口14725) │               │  ├─ GumJSWebSocket.dylib │
└──────────────┘               │  │  ├─ GumJS 引擎        │
                               │  │  └─ WebSocket 客户端   │
                               │  └─ 执行注入的 JS 脚本    │
                               └─────────────────────────┘
```

## 功能

- **Settings 配置**：在 iOS 设置中选择目标 App、输入 WebSocket URI
- **WebSocket 热更新**：修改 JS 文件后自动推送到设备
- **大脚本分块传输**：支持超过 5KB 的脚本自动分块
- **Stalker 自排除**：自动排除自身内存区域，避免 Stalker 冲突
- **Stealth Frida**：使用隐蔽版 GumJS devkit，降低检测风险

## 安装

### 方式一：GitHub Actions 自动编译

1. Fork 或 push 到 GitHub
2. 进入 Actions 页面，运行 `Build iOS Tweak`
3. 下载产物中的 `.deb` 文件
4. 传输到越狱设备，使用 `dpkg -i xxx.deb` 安装
5. 注销或重启 SpringBoard

### 方式二：本地编译（需要 macOS + Theos）

```bash
# 安装 Theos（如果还没装）
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

# 下载 devkit
chmod +x scripts/download_devkit.sh
./scripts/download_devkit.sh

# 编译
make package FINALPACKAGE=1
```

## 使用方法

### 1. 配置目标 App

打开 iOS **设置** → **GumJS WebSocket**：

1. 打开 **Enabled** 总开关
2. 点击 **Add App**，输入目标 App 的 Bundle ID（如 `com.example.app`）
3. 点击已添加的 App，配置：
   - **WebSocket URI**：PC 端 server.py 的地址（如 `ws://192.168.1.100:14725/ws`）
   - **Delay**：注入延迟（毫秒），0 表示立即注入
   - **Enable Injection**：开关

### 2. 启动 PC 端服务器

```bash
pip install websockets aiofiles watchdog
python server.py your_script.js
```

### 3. 打开目标 App

App 启动时会自动连接 WebSocket 服务器并加载脚本。修改 `your_script.js` 后会自动热更新推送。

## WebSocket 消息协议

| type     | 方向           | 说明                     |
|----------|----------------|--------------------------|
| `start`  | server → client | 首次加载脚本（同步）      |
| `script` | server → client | 热更新脚本（异步重建）    |
| `post`   | server → client | 向已有脚本 post 消息      |
| `end`    | server → client | 卸载脚本并退出            |
| `log`    | client → server | 脚本日志回传              |
| `error`  | client → server | 脚本错误信息              |

## 配置文件

路径：`/var/mobile/Library/Preferences/com.gjws.config.plist`

```xml
<dict>
    <key>enabled</key>
    <true/>
    <key>apps</key>
    <dict>
        <key>com.example.app</key>
        <dict>
            <key>inject</key>  <true/>
            <key>uri</key>     <string>ws://192.168.1.100:14725/ws</string>
            <key>delay</key>   <integer>0</integer>
        </dict>
    </dict>
</dict>
```

## 与 Android 版差异

| 项目       | Android (Zygisk)               | iOS (本项目)                      |
|------------|--------------------------------|-----------------------------------|
| 注入方式    | Zygisk (Zygote hook)           | MobileSubstrate/Substitute       |
| WebSocket  | libsoup (GLib 集成)            | NSURLSessionWebSocketTask (原生)  |
| 配置界面    | /data/data/.../config.json     | Settings.app PreferenceBundle    |
| JS 引擎    | QuickJS                        | QuickJS                          |
| Devkit     | frida-gumjs + frida-sdk        | stealth-frida-gumjs-devkit       |

## License

MIT
