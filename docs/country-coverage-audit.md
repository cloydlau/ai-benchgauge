# 国家资料覆盖排查（2026-10-16）

范围：公开共享服务的八类榜单，共 895 个条目。修复前 136 条缺失：54 条缺少开发者，其余为国家查询失败或别名未统一。快照、线上代码备份、仅修改国家/身份规则文件的发布包及逐项核对记录保存在忽略目录 `work/country-audit/`。

处理原则：国家按实际模型开发主体或研究机构归属；二次训练模型不继承基座厂商。缺失开发者仅以完整型号匹配，不替换为其他开发者，不匹配未知微调版；已确认的 Microsoft、InclusionAI、Pika Art 仅规范为同一开发主体的标准名称。新录入 41 个开发主体的国家资料、49 个精确型号归属；统一 Microsoft、InclusionAI、Pika Art 等别名，并确保输出名称可被旧客户端直接归一化为国家资料的身份键。Swift 国家兜底从同一 `fc/country-catalog.json` 生成，避免两份手写目录漂移。

## 线上核对结果

国家资料已从 759/895 提高到 890/895，本次补齐 131 条；除 Arena 文本榜保留以下 5 条未知外，其余七类榜单的现有条目全部覆盖。发布只修改 `brand-catalog.json`、`country-catalog.json`、`leaderboard-policy.json` 与 `countries.mjs`，未写入排行榜快照或修改函数配置。旧客户端按已有厂商归一化规则即可校验修复后的国家标识。

核对期间综合榜的两份快照发生独立刷新，文本榜 20 个既有条目的名称格式改变；逐模型 ID 核对未发现排名、分数或模型 ID 改变，不将名称/抓取时间变化说成由本次修复保留不变。每个修复条目的国家值另与固定回归案例核对；小程序通过真实响应的归一化、国旗、模型/公司国家筛选逻辑检查。

## 国家资料依据

同一品牌的服务销售实体、海外办公室或模型托管方不替代开发主体。Cohere 采用其加拿大开发主体；Recraft 官方说明其总部位于英国，虽在美国成立；Pruna 使用其官方合同所列德国主体；Stability 使用英国注册开发主体，区别于美国服务实体。研究模型采用发布机构的所在地。

| 开发者 | 国家代码 | 主要依据 |
| --- | --- | --- |
| Cohere (`cohere`) | CA | [官方资料](https://cohere.com/privacy) |
| Ant Group (`antgroup`) | CN | [官方资料](https://www.antgroup.com/en/about/our-offices) |
| Inception AI (`inceptionai`) | US | [官方资料](https://www.inceptionlabs.ai/blog/mercury-refreshed) |
| IBM (`ibm`) | US | [官方资料](https://www.ibm.com/contact/global) |
| Ai2 (`ai2`) | US | [官方资料](https://allenai.org/about) |
| Prime Intellect (`primeintellect`) | US | [官方资料](https://www.primeintellect.ai/careers) |
| Nexusflow (`nexusflow`) | US | [官方资料](https://people.eecs.berkeley.edu/~banghua/cv.pdf) |
| AI21 Labs (`ai21labs`) | IL | [官方资料](https://www.ai21.com/terms-policies/privacy-policy/) |
| Reka (`reka`) | US | [官方资料](https://www.reka.ai/privacy-policy) |
| 01.AI (`01ai`) | CN | [官方资料](https://www.01.ai/Yi) |
| Shanghai AI Laboratory (`shanghaiailaboratory`) | CN | [官方资料](https://huggingface.co/internlm/internlm2_5-20b-chat) |
| Princeton NLP (`princetonnlp`) | US | [官方资料](https://pli.princeton.edu/blog/2024/simpo-new-way-teach-ai-models-follow-human-preferences) |
| Databricks (`databricks`) | US | [官方资料](https://www.databricks.com/sites/default/files/legal/databricks-msa-9-02-2025.pdf) |
| MosaicML (`mosaicml`) | US | [官方资料](https://www.databricks.com/company/newsroom/press-releases/databricks-completes-acquisition-mosaicml) |
| Snowflake (`snowflake`) | US | [官方资料](https://www.sec.gov/Archives/edgar/data/1640147/000164014725000052/snow-20250131.htm) |
| LMSYS (`lmsys`) | US | [官方资料](https://lmsys.org/blog/2023-03-30-vicuna/) |
| UC Berkeley (`ucberkeley`) | US | [官方资料](https://starling.cs.berkeley.edu/) |
| University of Washington (`universityofwashington`) | US | [官方资料](https://arxiv.org/abs/2305.14314) |
| Hugging Face (`huggingface`) | US | [官方资料](https://huggingface.co/privacy) |
| Together AI (`togetherai`) | US | [官方资料](https://www.together.ai/terms-of-service) |
| Nomic AI (`nomicai`) | US | [官方资料](https://www.nomic.ai/about) |
| LAION (`laion`) | DE | [官方资料](https://laion.ai/gep-policy/) |
| Stability AI (`stabilityai`) | GB | [官方资料](https://find-and-update.company-information.service.gov.uk/company/12295325) |
| Poolside (`poolside`) | US | [官方资料](https://www.linkedin.com/company/poolsideai) |
| Recraft (`recraft`) | GB | [官方资料](https://www.recraft.ai/about) |
| HiDream (`hidream`) | CN | [官方资料](https://www.hidreamai.com/home) |
| Pruna AI (`prunaai`) | DE | [官方资料](https://docs.api.pruna.ai/terms-dpa) |
| Vidu (`vidu`) | CN | [官方资料](https://platform.vidu.cn/docs/open-platform-privacy-policy) |
| Leonardo AI (`leonardoai`) | AU | [官方资料](https://leonardo.ai/privacy-policy) |
| Bria (`bria`) | IL | [官方资料](https://downloads.regulations.gov/COLC-2023-0006-8396/attachment_1.pdf) |
| VectorSpaceLab (`vectorspacelab`) | CN | [官方资料](https://vectorspacelab.github.io/OmniGen/) |
| Lightricks (`lightricks`) | IL | [官方资料](https://static.lightricks.com/legal/ai-terms-of-use.html) |
| Pika (`pika`) | US | [官方资料](https://pika.art/privacy-policy) |
| Creatify (`creatify`) | US | [官方资料](https://creatify.ai/ambassador) |
| Kandinsky (`kandinsky`) | RU | [官方资料](https://github.com/kandinskylab/kandinsky-5) |
| Genmo AI (`genmoai`) | US | [官方资料](https://www.genmo.ai/terms-of-service) |
| Institute of Foundation Models (`instituteoffoundationmodels`) | AE | [官方资料](https://ifm.ai/k2/press-release/) |
| Kuaishou (`kuaishou`) | CN | [官方资料](https://ir.kuaishou.com/corporate-information) |
| Nous Research (`nousresearch`) | US | [官方资料](https://shop.nousresearch.com/policies/privacy-policy) |
| Stanford (`stanford`) | US | [官方资料](https://crfm.stanford.edu/2023/03/13/alpaca.html) |
| Technology Innovation Institute (`technologyinnovationinstitute`) | AE | [官方资料](https://www.tii.ae/news/uaes-technology-innovation-institute-launches-falcon-foundation-champion-open-sourcing) |

## 缺失开发者的精确型号归属

下列资料确认模型的开发者，国家依据见上表。ChatGLM、PixVerse、StepFun 复用原有国家目录。Dolly 的开发记录见 [Databricks 官方项目](https://github.com/databrickslabs/dolly)，Koala 见 [Berkeley 官方发布](https://bair.berkeley.edu/blog/2023/04/03/koala/)，SmolLM 见[官方模型卡](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct)。

| 型号（完整匹配，忽略大小写及两端空白） | 开发者 | 发布资料 |
| --- | --- | --- |
| `intellect-3` | Prime Intellect | [模型发布资料](https://huggingface.co/PrimeIntellect/INTELLECT-3) |
| `yi-lightning`, `yi-1.5-34b-chat`, `yi-34b-chat` | 01.AI | [模型发布资料](https://www.01.ai/Yi) |
| `athene-v2-chat`, `athene-70b-0725` | Nexusflow | [模型发布资料](https://huggingface.co/Nexusflow/Athene-V2-Chat) |
| `jamba-1.5-large`, `jamba-1.5-mini` | AI21 Labs | [模型发布资料](https://huggingface.co/ai21labs/AI21-Jamba-Large-1.5) |
| `reka-core-20240904`, `reka-flash-20240904`, `reka-flash-21b-20240226-online`, `reka-flash-21b-20240226` | Reka | [模型发布资料](https://reka.ai/news/reka-flash-updates) |
| `gemma-2-9b-it-simpo` | Princeton NLP | [模型发布资料](https://pli.princeton.edu/blog/2024/simpo-new-way-teach-ai-models-follow-human-preferences) |
| `zephyr-orpo-141b-a35b-v0.1`, `zephyr-7b-beta`, `zephyr-7b-alpha`, `smollm2-1.7b-instruct` | Hugging Face | [模型发布资料](https://huggingface.co/HuggingFaceH4/zephyr-orpo-141b-A35b-v0.1) |
| `dbrx-instruct-preview`, `dolly-v2-12b` | Databricks | [模型发布资料](https://www.databricks.com/blog/introducing-dbrx-new-state-art-open-llm) |
| `internlm2_5-20b-chat` | Shanghai AI Laboratory | [模型发布资料](https://huggingface.co/internlm/internlm2_5-20b-chat) |
| `snowflake-arctic-instruct` | Snowflake | [模型发布资料](https://huggingface.co/Snowflake/snowflake-arctic-instruct) |
| `tulu-2-dpo-70b` | Ai2 | [模型发布资料](https://huggingface.co/allenai/tulu-2-dpo-70b) |
| `vicuna-33b`, `vicuna-13b`, `vicuna-7b`, `fastchat-t5-3b` | LMSYS | [模型发布资料](https://lmsys.org/blog/2023-03-30-vicuna/) |
| `starling-lm-7b-beta`, `starling-lm-7b-alpha`, `koala-13b` | UC Berkeley | [模型发布资料](https://starling.cs.berkeley.edu/) |
| `nous-hermes-2-mixtral-8x7b-dpo` | Nous Research | [模型发布资料](https://huggingface.co/NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO) |
| `mpt-30b-chat`, `mpt-7b-chat` | MosaicML | [模型发布资料](https://www.databricks.com/blog/mpt-7b) |
| `guanaco-33b` | University of Washington | [模型发布资料](https://github.com/artidoro/qlora) |
| `stripedhyena-nous-7b` | Together AI | [模型发布资料](https://huggingface.co/togethercomputer/StripedHyena-Nous-7B) |
| `gpt4all-13b-snoozy` | Nomic AI | [模型发布资料](https://huggingface.co/nomic-ai/gpt4all-13b-snoozy) |
| `chatglm3-6b`, `chatglm2-6b`, `chatglm-6b` | Z.ai | [模型发布资料](https://huggingface.co/zai-org/chatglm-6b) |
| `oasst-pythia-12b` | LAION | [模型发布资料](https://github.com/LAION-AI/Open-Assistant) |
| `stablelm-tuned-alpha-7b`, `stable-diffusion-v35-large` | Stability AI | [模型发布资料](https://huggingface.co/stabilityai/stablelm-tuned-alpha-7b) |
| `kat-coder-pro-v1` | Kuaishou | [模型发布资料](https://github.com/kwaipilot/KAT-Coder-Agent/blob/main/KAT-Coder_Report.md) |
| `p-image`, `p-video` | Pruna AI | [模型发布资料](https://docs.api.pruna.ai/) |
| `pixverse-v5.6` | PixVerse | [模型发布资料](https://pixverse.ai/) |
| `ltx-2-19b` | Lightricks | [模型发布资料](https://github.com/Lightricks/LTX-2) |
| `claude code - step 5 preview` | StepFun | [模型发布资料](https://artificialanalysis.ai/agents/coding-agents) |
| `alpaca-13b` | Stanford | [模型发布资料](https://crfm.stanford.edu/2023/03/13/alpaca.html) |
| `falcon-180b-chat` | Technology Innovation Institute | [模型发布资料](https://huggingface.co/tiiuae/falcon-180B-chat) |

## 保留未知的条目

这五条已核对开发来源，但当前资料无法支持唯一的开发主体总部国家。不能据姓名、国籍、语言、基座模型、推理服务商或个人资料猜测国家；未来有可核实依据后再补充。

| 条目 | 可确认来源 | 未确定原因 |
| --- | --- | --- |
| `openchat-3.5`、`openchat-3.5-0106` | [OpenChat 官方团队](https://huggingface.co/openchat) | 跨机构开源团队，未确认单一总部主体 |
| `openhermes-2.5-mistral-7b` | [Teknium 官方模型卡](https://huggingface.co/teknium/OpenHermes-2.5-Mistral-7B) | 个人作者发布，不能直接当作 Mistral 或其他公司产品 |
| `dolphin-2.2.1-mistral-7b` | [Dolphin 官方模型卡](https://huggingface.co/dphn/dolphin-2.2.1-mistral-7b) | 个人/社区二次训练，未核实单一开发主体总部 |
| `RWKV-4-Raven-14B` | [BlinkDL 官方权重](https://huggingface.co/BlinkDL/rwkv-4-raven) | 个人作者及分布式项目，未核实该型号的单一开发主体总部 |

## 复查

验证通过：61 项服务端测试、10 项 Swift 国家测试、95 项小程序测试及小程序构建。线上回读另外验证了全部有国家资料的条目能通过旧版厂商身份规则，以及小程序对真实响应的国旗、模型和公司国家筛选。

`Tests/fixtures/country-coverage.json` 保存本次 136 条缺失及 Nova、原版 Llama、原版 Gemma 的对照案例。服务端测试覆盖失败缓存、型号归属、未知变体、明确的其他开发者与原榜数据保留；Swift 测试覆盖缓存往返、国家筛选和公司聚合。

使用只读 GET 保存八类共享响应后，可重复执行（不访问原始榜单，也不触发刷新）：

```sh
node Scripts/audit-country-coverage.mjs \
  work/country-audit/artificialAnalysis*-after.json \
  work/country-audit/arena*-after.json \
  work/country-audit/codeArenaWebDev-after.json
```

加 `--require-complete` 可在存在缺失时返回非零退出码。报告区分 `missing-developer`、`missing-country` 与 `developer-mismatch`，不会将任意国家值误认作有效覆盖。
