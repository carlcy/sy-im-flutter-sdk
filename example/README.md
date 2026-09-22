# sy_im_flutter_sdk_example

## 生产基址（2026-09-15）

- API: `http://47.105.48.196`
- 信令: `ws://47.105.48.196/ws/signaling`（RTC；须 `?token=`）
- 文档: `docs/SDK_RTC.md` / `docs/SDK_IM.md`
- 下载: `http://47.105.48.196/downloads/`

本机调试仍可用 `10.0.2.2:8080`（Android 模拟器）或 `127.0.0.1`。


Minimal demo: create / login / logout / sendTextMessage.  
Calls will throw `UnimplementedError` until native OpenIM is wired.
