# 值班提醒 隐私政策 / Privacy Policy

更新日期：2026 年 11 月 23 日

## 中文

「值班提醒」是排班工具。App 不会默认将值班资料发送给第三方；只有你主动使用下述联网功能时，才会发送该功能所需的内容。

- **账号密码**：你填写的值班网站账号密码只保存在本机的钥匙串里，只用来登录你自己单位的值班网站。
- **排班数据**：从值班网站读到的排班、工作量统计等只保存在本机，不会发送给开发者或任何第三方。
- **工作留痕**：拍照、录音、文字记录只保存在本机（可选面容 ID 加锁）。录音转文字默认用手机本机识别；只有你在设置里关掉「只在手机上识别」时，才会使用苹果的语音识别服务。
- **数传计划图片识别（DeepSeek）**：直接导入 Excel 或粘贴表格不发送资料。仅当你拍摄或选择一张图并明确确认发送时，App 才向 DeepSeek 发送该图的画面内容（不含原始照片定位等元数据），用于提取表格。请勿使用未经许可外发的图片。DeepSeek API Key 只保存在本机钥匙串，用于验证你向 DeepSeek 发出的请求。你可随时在 App 内移除已保存的 Key。
- **DeepSeek 问答**：只会将你主动发送的文字和当前对话所需的上下文发送给 DeepSeek。不会自动读取或上传排班、站名表、联系人、计划图片或其他 App 资料。请勿发送未经许可外发的资料。问答复用本机钥匙串中的 DeepSeek API Key。
- **微信推送**：只有你自己开启并填写 PushPlus 令牌后，App 才会把提醒内容经 PushPlus 发到你的微信。默认只发你自己的排班；同事的排班变动、网站公告要你在设置里另外打开才会发。
- **节假日数据**：App 会从公开的节假日数据源下载法定节假日安排，不附带任何个人信息。
- **统计与广告**：App 不含任何统计、追踪或广告代码。

如需移除 DeepSeek Key，请先在 App 内移除，再卸载 App。有问题请联系：在 TestFlight 里点「发送 Beta 版反馈」。

## English

ShiftReminder is a duty-roster tool. It does not send duty data to third parties by default. The optional connected features below send only the data needed for the feature you choose.

- Your duty-website credentials are stored only in the device Keychain and used only to sign in to your own organization's website.
- Rosters and statistics read from that website stay on the device and are never sent to the developer or third parties.
- Work-log photos, recordings and notes stay on the device. Speech is transcribed on-device by default; Apple's speech service is used only if you turn off on-device recognition.
- Plan image recognition (DeepSeek): Spreadsheet and clipboard imports do not send plan data. After you capture or select and explicitly confirm an image, the app sends its visual content, without the original photo metadata such as location, to DeepSeek to extract the table. Do not submit images you are not authorized to share. Your DeepSeek API key is stored in this device’s Keychain, used to authenticate your requests to DeepSeek, and can be removed in the app.
- DeepSeek chat sends only the text you choose to submit and the relevant context in that conversation. It does not automatically access or send rosters, station rules, contacts, plan images, or other app data. Do not send information you are not authorized to share. Chat reuses the DeepSeek API key in the device Keychain.
- WeChat push (PushPlus) is used only if you enable it and enter your own token. By default only your own shifts are sent; colleagues' roster changes and site notices are sent only if you turn that on separately.
- Public-holiday data is downloaded from a public source without any personal information.
- No analytics, tracking or advertising.

To remove the DeepSeek key, remove it in the app before uninstalling.
