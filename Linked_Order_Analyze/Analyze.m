//
//  Analyze.m
//  Linked_Order_Analyze
//
//  Created by 李扬 on 2021/1/17.
//

#import "Analyze.h"
#import "Util.h"

/*
 二进制重排技术 线下量化分析总体思路：
 1. 读取 Linked Map 文件，获取 __Text 代码区的起始地址和块大小，分析得到需要分配的虚拟内存页个数
 2. 获取 __Text 代码区 所有symbol的地址、大小和具体符号，存入字典
 3. 根据字典中起始地址和所有symbol大小总和，校验是否和1描述相符 // 发现有重复 symbol 和 symbol地址跳跃现象
 4. 分析 二进制重排文件order所包含的symbol，和2中字典做映射，得到symbol对应的地址和内存占用大小
 5. 分析 order文件中所包含的symbol，得到占用原始虚拟内存页个数
 6. 将 order文件中所包含的symbol内存占用相加，分析得到 重排后所占虚拟内存页个数
 7. 原始虚拟内存页个数 - 重排后所占虚拟内存页个数 = 节省的虚拟内存页个数
 8. 节省的虚拟内存页个数 * 每一个内存缺页中断大致的处理时间 = 节省的内存缺页中断处理总时间
 */

// 链接文件和order文件根目录
static NSString * const BASE_PATH = @"/Users/liyang/Desktop/1";
// 链接文件名
static NSString * const LINKED_MAP = @"linked_map.txt";
// order 文件名
static NSString * const LB_ORDER = @"lb.order";
// iOS平台虚拟内存页大小(16k)
static unsigned long long const VM_PAGE_SIZE = 16 * 1024;

// 链接文件 __Text 映射字典 key:symbol value:[起始地址, 占用内存大小]
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *linkedTextDictM;
// 排序文件 __Text 映射字典 key:symbol value:[起始地址, 占用内存大小]
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *orderTextDictM;

// 处理每个内存缺页中断所需要的时间:0.1ms ~ 1ms之间，取中位数 0.5ms
static double const PAGE_FAULT_CONST_ESTIMATE_TIME = 0.5;

@implementation Analyze

+ (void)start
{
    // 链接文件完整路径
    NSString *linked_map_path = [NSString stringWithFormat:@"%@/%@", BASE_PATH, LINKED_MAP];
    // 排序文件完整路径
    NSString *order_path = [NSString stringWithFormat:@"%@/%@", BASE_PATH, LB_ORDER];

    // 链接文件内容
    NSError *linkedMapContentError;
    NSString* linkedMapFileContents = [NSString stringWithContentsOfFile:linked_map_path encoding:NSASCIIStringEncoding error:&linkedMapContentError];
    if (linkedMapContentError)
    {
        abort();
        return;
    };
    
    // __text 开始地址 十进制
    __block unsigned long long sectionTextStartAddressDecimalValue = 0;
    // __text 结束地址 十进制
    __block unsigned long long sectionTextEndAddressDecimalValue = 0;
    // __Text 所占用虚拟内存页个数
    __block unsigned long long sectionTextLinkedVMPageCount = 0;
    
    // 1. 分析 linked map 文件，得出分配多少个虚拟内存页;section __Text __text 开始地址 十进制;section __Text __text 结束地址 十进制
    NSRegularExpression *regexLinkedMap = [NSRegularExpression
                                         regularExpressionWithPattern:@"(0x[A-F\\d]*)\\s+(0x[A-F\\d]*)\\s+__TEXT\\s+__text"
                                         options:0
                                         error:nil];
    [regexLinkedMap enumerateMatchesInString:linkedMapFileContents options:0 range:NSMakeRange(0, linkedMapFileContents.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        
        if ([result numberOfRanges] != 3) return;
        
        // 分析 linked_map 文件，判断出虚拟内存页个数
        // 匹配的 section __Text __text 字符串行
        NSString *sectionTextLine = [linkedMapFileContents substringWithRange:result.range];
        NSLog(@"----__Text:%@", sectionTextLine);
        
        // 匹配 section __Text __text 首地址
        NSString *sectionTextStartAddressHexStr = [linkedMapFileContents substringWithRange:[result rangeAtIndex:1]];
        sectionTextStartAddressDecimalValue = [Util decialFromHexStr:sectionTextStartAddressHexStr];
        // 匹配 section __Text __text 内存映射大小
        NSString *sectionTextSizeHexStr = [linkedMapFileContents substringWithRange:[result rangeAtIndex:2]];
        
        // 分析分配的虚拟内存页个数
        unsigned long long section_text_decimal_size = [Util decialFromHexStr:sectionTextSizeHexStr];
        sectionTextLinkedVMPageCount = section_text_decimal_size / VM_PAGE_SIZE + 1;
        
        NSLog(@"----linked __text vm count:%llu", sectionTextLinkedVMPageCount);
        
        sectionTextEndAddressDecimalValue = sectionTextStartAddressDecimalValue + section_text_decimal_size;
    }];
    
    // 2. 分析 linked map 文件，在开始地址和结束地址之间额symble字典
    // __Text 所有 symbol 占用虚拟内存大小总和，发现有symbol重复和地址跳跃的现象
    __block unsigned long long linkedTextSumAllSymbolSize = 0;
    // __Text 所有 symbol 个数，和 sumAllSymbolSize 一起反推 1 中数据的正确性。个数是一直的
    __block unsigned long long linkedTextSymbolLineCount = 0;
    
    // __Text symbol 重复的情况
    __block NSMutableArray *linkedTextSymbolDuplicatedArrM = [NSMutableArray array];
    // 预计算下一行 symbol 起始地址，以确定地址跳跃情况
    __block unsigned long long linkedTextNextSymbolPreComputeStartDecialValue = 0;
    // __Text symbol start + size != next start 地址跳跃情况
    __block NSMutableArray *linkedTextSymbolStartAddressJumpedArrM = [NSMutableArray array];
    
    linkedTextDictM = [NSMutableDictionary dictionary];
    NSRegularExpression *regexLinkedMapLines = [NSRegularExpression
                                         regularExpressionWithPattern:@"(0x[A-F\\d]*)\\s+(0x[A-F\\d]*)\\s+\\[.*\\] (.+)"
                                         options:0
                                         error:nil];
    [regexLinkedMapLines enumerateMatchesInString:linkedMapFileContents options:0 range:NSMakeRange(0, linkedMapFileContents.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        
        if ([result numberOfRanges] != 4) return;
        
        // 匹配的 symbol __Text 一行行的字符串
        NSString *linkedTextSymbolLine = [linkedMapFileContents substringWithRange:result.range];
        
        // symble 地址
        NSString *linkedTextSymbolStartAddressHexStr = [linkedMapFileContents substringWithRange:[result rangeAtIndex:1]];
        unsigned long long linkedTextSymbolStartAddressDecimalValue = [Util decialFromHexStr:linkedTextSymbolStartAddressHexStr];
        
        // symbol 大小
        NSString *linkedTextSymbolSizeHexStr = [linkedMapFileContents substringWithRange:[result rangeAtIndex:2]];
        unsigned long long linkedTextSymbolSizeDecimalValue = [Util decialFromHexStr:linkedTextSymbolSizeHexStr];
        // 具体的 symbol
        NSString *symbol = [linkedMapFileContents substringWithRange:[result rangeAtIndex:3]];
        
        // 地址在 section __Text 之间
        if (linkedTextSymbolStartAddressDecimalValue >= sectionTextStartAddressDecimalValue && linkedTextSymbolStartAddressDecimalValue < sectionTextEndAddressDecimalValue)
        {
            NSLog(@"----linked_symbol:%@", linkedTextSymbolLine);
            
            // 计算 linked __Text 符号所占用虚拟内存页大小 用来和 1 做反向验证
            linkedTextSumAllSymbolSize += linkedTextSymbolSizeDecimalValue;
            // 计算 linked __Text 符号个数 用来和 1 做反向验证
            linkedTextSymbolLineCount++;
            
            // 地址跳跃处理
            if (linkedTextNextSymbolPreComputeStartDecialValue != 0 && linkedTextNextSymbolPreComputeStartDecialValue != linkedTextSymbolStartAddressDecimalValue)
            {
                [linkedTextSymbolStartAddressJumpedArrM addObject:linkedTextSymbolLine];
            }
            linkedTextNextSymbolPreComputeStartDecialValue = linkedTextSymbolStartAddressDecimalValue + linkedTextSymbolSizeDecimalValue;
            
            // 符号重复 忽略
            if (linkedTextDictM[symbol] != nil)
            {
                [linkedTextSymbolDuplicatedArrM addObject:symbol];
                return;
            }
            
            // 存入字典
            [linkedTextDictM setValue:@[@(linkedTextSymbolStartAddressDecimalValue), @(linkedTextSymbolSizeDecimalValue)] forKey:symbol];
        }
    }];
    
    // 3. 根据字典中起始地址和所有symbol大小总和，校验是否和1描述相符
    // 个数相符，但发现有symbol重复和地址跳跃的现象
    
    // 4. 分析 二进制重排文件order所包含的symbol，和 2 中字典做映射，得到symbol对应的地址和内存占用大小
    // 5. 分析 order文件中所包含的symbol，得到占用原始虚拟内存页个数
    orderTextDictM = [NSMutableDictionary dictionary];
    // order 中symbol的个数
    __block unsigned long long orderSymbolLineCount = 0;
    // order 中symbol所占用内存页分布情况
    __block NSMutableSet<NSNumber *> *orderVMPageSetM = [NSMutableSet set];
    // order 中 所有 symbol 占用大小总和，除以 VM_PAGE_SIZE 可以得到排序后占用的连续虚拟内页个数
    __block unsigned long long orderSumAllSymbolSize = 0;
    
    // order 文件内容
    NSError *orderContentError = nil;
    NSString* orderpFileContents = [NSString stringWithContentsOfFile:order_path encoding:NSASCIIStringEncoding error:&orderContentError];
    if (orderContentError)
    {
        abort();
        return;
    };

    NSRegularExpression *regexOrder = [NSRegularExpression
                                         regularExpressionWithPattern:@"(.+)"
                                         options:0
                                         error:nil];
    [regexOrder enumerateMatchesInString:orderpFileContents options:0 range:NSMakeRange(0, orderpFileContents.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if ([result numberOfRanges] != 2) return;

        // 得到 order 一行行 symbol 符号
        NSString *orderSymbolLine = [orderpFileContents substringWithRange:[result rangeAtIndex:1]];
        
        // 计算 order symbol 行数
        orderSymbolLineCount++;
    
        NSArray<NSNumber *> *arr = linkedTextDictM[orderSymbolLine];
        if (arr == nil)
        {
            // order 对应 linked 文件，未命中的情况
            NSLog(@"");
        }
        
        // 获得 symbole 十进制 的地址
        unsigned long long orderSymbolStartAddressDecimalValue = [arr.firstObject unsignedLongLongValue];
        unsigned long long orderSymbolRelativeStartAddressDecimalValue = orderSymbolStartAddressDecimalValue - sectionTextStartAddressDecimalValue;
        // 得到当前 symbole 所在的内存页序号index
        unsigned long long orderSymbolVMPageIndex = orderSymbolRelativeStartAddressDecimalValue / VM_PAGE_SIZE;
        [orderVMPageSetM addObject:@(orderSymbolVMPageIndex)]; // 得到被分配到了哪些虚拟内存页
        
        // 获得 symbole 十进制 的占用内存大小
        unsigned long long orderSymbolSizeDecimalValue = [arr.lastObject unsignedLongLongValue];
        orderSumAllSymbolSize += orderSymbolSizeDecimalValue;
    }];
    
    // 6. 将 order文件中所包含的symbol内存占用相加，分析得到 重排后所占虚拟内存页个数
    unsigned long long orderSymbolAllVMPageCount = orderSumAllSymbolSize / VM_PAGE_SIZE + 1;
    
    printf("\n---> 分析结果：");
    printf("\n lined map __Text(链接文件)：");
    printf("\n   起始地址：%s", [[Util hexFromDecimal:sectionTextStartAddressDecimalValue] UTF8String]);
    printf("\n   结束地址：%s", [[Util hexFromDecimal:sectionTextEndAddressDecimalValue] UTF8String]);
    printf("\n   分配的虚拟内存页个数：%llu", sectionTextLinkedVMPageCount);
    printf("\n order symbol(重排文件)：");
    printf("\n   需要重排的符号个数：%llu", orderSymbolLineCount);
    printf("\n   分布的虚拟内存页个数：%lu", (unsigned long)orderVMPageSetM.count);
    printf("\n   二进制重排后分布的虚拟内存页个数：%llu", orderSymbolAllVMPageCount);
    // 7. 原始虚拟内存页个数 - 重排后所占虚拟内存页个数 = 节省的虚拟内存页个数
    printf("\n   内存缺页中断减少的个数：%llu", orderVMPageSetM.count - orderSymbolAllVMPageCount);
    // 8. 节省的虚拟内存页个数 * 每一个内存缺页中断大致的处理时间 = 节省的内存缺页中断处理总时间
    printf("\n   预估节省的时间：%.0fms\n", (orderVMPageSetM.count - orderSymbolAllVMPageCount) * PAGE_FAULT_CONST_ESTIMATE_TIME);
}

@end
