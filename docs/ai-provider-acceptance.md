# 多服务商 AI 问答交接

- 首页左上角仍打开原 DeepSeek 页，点「AI 工具箱」进入四家文字聊天或独立工具。DeepSeek 两档模型与思考选择、识图及标书流程不改变。文字聊天不自动读取业务数据，也不把出图和语音混进聊天。
- 每个服务商须由使用者在各自页面填写自己的 API Key。为自用测试使用权限受限的项目密钥和用量限制；不打包、同步、记录或向他人分发密钥。若面向公众提供开发者统一账户能力，应改为服务端保管密钥，不把开发者的 Key 随 App 发布。
- 「获取模型／刷新模型」请求官方目录，不写死全套模型；目录不等于当前 Key 对每项调用的权限。只有有文字问答调用方式的模型进入选择菜单，筛出的其他目录项只作展示。GPT / Gemini / Claude / Grok 的首版答复一次返回，不伪装成流式或通用的深度开关。
- 上线前在 iPhone、iPad 签名构建各验证：无 Key 可进入四个页面、不发送；用各家本人授权的受限测试 Key 获取目录；各实际选择一个文字模型，以无敏感信息的短句测试两轮；验证错误 Key、失效模型、限流、网络中断与取消；替换、删除 Key 不留之前的会话/模型权限。切换模型的上下文只在同一家内；切换服务商不自动带入任何历史、文件或站名表。删除测试 Key 前确认不影响其他页面。
- 先核对 Xcode 编译及上述实测，不把模拟响应或 SwiftUI 语法检查当作真机证据。尚未授权推送或发布；等合并后的精确提交通过验收后再处理 TestFlight。

## AI 工具箱扩展

- 首页左上角 → DeepSeek → AI 工具箱。文字聊天保留，菜单新增出图、语音、代码与工作工具。
- 出图：文本生成单张图，提供 GPT Image、Gemini Nano Banana、Grok Imagine 的已适配模型。各自独立计费，成功后可预览并经系统分享，不承诺任何项目都有图像授权。在每家测试正常生成、错误 Key、限流、取消、无有效图片及 iPhone/iPad 分享。
- 语音：本机朗读和 xAI 云朗读；OpenAI 转写主动选中的音频，支持文件或 60 秒以内的前台麦克风录音，先试听再确认上传。该录音功能不是实时通话。另有独立的实时入口。实测本机可听、云音频可播放及系统音频中断、20 MB 超限、取消、无权限、导入取消及内容确认后才发送。
- 代码工具：生成、解释、审阅并复制/分享文本，不编译、执行或部署。工作工具：生成文档、总结、交班草稿；只读你主动提交且获准外发的文字，不自动取值班数据或改变记录。原计划复核、外发预览及标书仍是独立功能。每次关键测试只用虚构资料。
- 没有真机、API Key 或资格时，把对应项标为未验证。旧的 TestFlight 冒烟脚本不能替代本节。

官方接口参考：[OpenAI Images](https://developers.openai.com/api/reference/resources/images/methods/generate)、[Gemini 图片生成](https://ai.google.dev/gemini-api/docs/image-generation)、[xAI 图片生成](https://docs.x.ai/developers/model-capabilities/images/generation)、[xAI 语音合成](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech)、[OpenAI 文件转写](https://developers.openai.com/api/docs/guides/speech-to-text)。

## OpenAI 实时语音通话（真实设备是发布门槛）

- 工具箱中的独立「实时语音通话」与录音转写分开。自用 BYOK 模式：OpenAI Key 仅用于向其官方 HTTPS 获取短时 Realtime 凭证，WebSocket 连接使用短时凭证，不发送聊天和业务数据。公开分发的统一项目密钥应改用可信服务端签发凭证。
- 在 iPhone、iPad 选个人获准测试的 Realtime 模型。确认拒绝麦克风时不连音频；取消外发确认时不启动会话；连通后至少两轮现场互答，确认不用上传文件。测扬声器／耳机回声与能否插话；播放被打断后应停止并按已播放位置截断。
- 验证静音、挂断、返回、应用失焦／锁屏、系统来电、耳机拔出、低网速错误、10 分钟上限和连续重拨均符合说明。用系统麦克风指示和服务端计量确认已停止传输。记录真实设备和模型，不把 Linux 事件样本当通话实测。
- 官方参考：[OpenAI Realtime WebSocket](https://developers.openai.com/api/docs/guides/voice-websockets)、[Realtime 会话与插话](https://developers.openai.com/api/docs/guides/realtime-conversations)。
