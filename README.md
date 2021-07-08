# Linked_Order_Analyze
App启动时间优化 二进制重排技术 线下量化预分析工具

目的：在没有上线之前可以分析出对App启动优化节省的大致时间，起到指导作用。(_具体能优化多少，以线上数据为准_)

建议：每隔三个月执行一次二进制重排更新，确保 PageFault 次数维持在一个降低的稳定的水平

---

### 大体思路：
```
 1. 读取 Linked Map 文件，获取 __Text 代码区的起始地址和块大小，分析得到需要分配的虚拟内存页个数
 2. 获取 __Text 代码区 所有symbol的地址、大小和具体符号，存入字典
 3. 根据字典中的起始地址和所有symbol大小的总和，校验是否和1描述相符 (_发现有重复 symbol 和 symbol地址跳跃现象_)
 4. 分析 二进制重排文件order所包含的symbol，和2中字典做映射，得到symbol对应的地址和内存占用大小
 5. 分析 order文件中所包含的symbol，得到需要占用的原始虚拟内存页个数
 6. 将 order文件中所包含的symbol内存占用大小相加，分析得到 重排后所占虚拟内存页个数
 7. 原始虚拟内存页个数 - 重排后所占虚拟内存页个数 = 节省的虚拟内存页个数
 8. 节省的虚拟内存页个数 * 每一个内存缺页中断大致的处理时间 = 节省的内存缺页中断处理总时间
 ```

---

### 使用之前：
1. 使用xcode编译出 linked_map.txt 和 lb.order 文件，并放在同一个目录
2. 修改下面的路径到上述两个文件的根目录
```
// 链接文件和order文件根目录
static NSString * const BASE_PATH = @"/Users/liyang/Desktop/1"; 
```

---

### 如何编译出 linked_map.txt 文件

1. 在 _Target -> Build Settings_ 下，找到 _Write Link Map File_ 来设置输出与否 , 默认是 no .

2. 修改完毕之后，_clean_ 一下，运行工程，_Products -> Show in Finder_，在mach-o文件上上层目录 _Intermediates.noindex_ 文件下找到一个txt文件。将其重命名为linked_map.txt

--- 

### 如何编译出 lb.order 文件

1. 在目标工程 _Target -> Build Settings -> Other C Flags_ 添加 _-fsanitize-coverage=func,trace-pc-guard_。

    如果有swfit代码，也要在 _Other Swift Flags_ 添加 _-sanitize-coverage=func_ 和_-sanitize=undefined_ 
    
    (如果有源码编译的Framework也要添加这些配置。CocoaPods引入的第三方库不建议添加此配置）

2. 将 _MMTracePCGuard_ 文件放入到目标工程
3. 将 _+[MMTracePCGuard analyze]_ 方法放到目标工程认为可以启动结束的位置调用，执行clean->build->run。根据自身工程复杂度的情况，等待几分钟或者十几分钟，就会在沙盒 Documents 的 temp 目录生成 lb.order 文件


---

最终输出示例：
```
---> 分析结果：
 linked map __Text(链接文件)：
   起始地址：0x100006A60
   结束地址：0x1021E75E8
   分配的虚拟内存页个数：2169
 order symbol(重排文件)：
   需要重排的符号个数：4630
   分布的虚拟内存页个数：392
   二进制重排后分布的虚拟内存页个数：99
   内存缺页中断减少的个数：293
   预估节省的时间：146ms
   ```

---
