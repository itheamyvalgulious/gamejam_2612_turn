# 人形刀客音效

把下列文件放进本目录，名称和扩展名用小写。表中以 WAV 为例，也可用 OGG 或 MP3。缺少的文件由游戏原有合成音补上。替换后重启「启动试玩」，在第 10 关听效果。

| 文件名 | 触发动作 |
| --- | --- |
| `charge.wav` | 开场低位蓄力，跟随蓄力进度播放 |
| `step.wav` | 巡战、追击和出刀落脚 |
| `swing_light.wav` | 轻挥刀 |
| `swing_heavy.wav` | 重挥刀 |
| `armor_snap.wav` | 击倒时甲片断裂 |
| `death.wav` | 击倒起始 |
| `knee_land.wav` | 击倒时膝盖触地 |
| `sword_drop.wav` | 落刀撞地 |
| `body_impact.wav` | 机体砸地 |

`charge` 从蓄力动画的当前位置播放。短文件会提前结束，长文件只播到蓄力音效的原定结束点。
