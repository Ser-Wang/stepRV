# pending dev decisions, implementations...

## 1. RAS feature gating - Pending~ (26-08-23 20:00)
> see 11_rv32im_bpu/doc/dev_log/task_v11_02_return_address_stack.md

What happened: 在ras模块内部，多处逻辑被feature开关相与，我认为这是不合理的，feature开关带来了逻辑中的门控，怪
What I want: 在逻辑中尽可能减少feature开关的影响，若能完全通过宏定义的处理解决则更好，希望是ifdef实现。
Current Status: 与AI初步讨论修改方案，发现尚有较大讨论空间。
                当前首要目标是快速review完RAS feature实现代码，然后进入Cache开发，
                故令RAS Feature开关事宜先 pending~

                