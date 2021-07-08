//
//  MMTracePCGuard.m
//  Linked_Order_Analyze
//
//  Created by 李扬 on 2021/1/17.
//  Copyright © 2021 taou. All rights reserved.
//

#import "MMTracePCGuard.h"
#import <dlfcn.h>
#import <libkern/OSAtomic.h>

void __sanitizer_cov_trace_pc_guard_init(uint32_t *start,
                                         uint32_t *stop) {
    static uint64_t N;  // Counter for the guards.
    if (start == stop || *start) return;  // Initialize only once.
    printf("INIT: %p %p\n", start, stop);
    for (uint32_t *x = start; x < stop; x++)
        *x = ++N;  // Guards should start from 1.
}

//原子队列
static OSQueueHead symboList = OS_ATOMIC_QUEUE_INIT;
//定义符号结构体
typedef struct{
    void * pc;
    void * next;
}SymbolNode;
 
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    //if (!*guard) return;  // Duplicate the guard check.

    void *PC = __builtin_return_address(0);

    SymbolNode * node = malloc(sizeof(SymbolNode));
    *node = (SymbolNode){PC,NULL};

    //入队
    // offsetof 用在这里是为了入队添加下一个节点找到 前一个节点next指针的位置
    OSAtomicEnqueue(&symboList, node, offsetof(SymbolNode, next));
}

//void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
//    if (!*guard) return;  // Duplicate the guard check.
//     
//    void *PC = __builtin_return_address(0);
//    Dl_info info;
//    dladdr(PC, &info);
//     
//    printf("-=-=-=-=-=-=-=-=nsname=%s\n\n",info.dli_sname);
//     
////    char PcDescr[1024];
////    printf("guard: %p %x PC %s\n", guard, *guard, PcDescr);
//}

@implementation MMTracePCGuard

+ (void)analyze
{
    NSMutableArray<NSString *> * symbolNames = [NSMutableArray array];
    while (true) {
        //offsetof 就是针对某个结构体找到某个属性相对这个结构体的偏移量
        SymbolNode * node = OSAtomicDequeue(&symboList, offsetof(SymbolNode, next));
        if (node == NULL) break;
        Dl_info info;
        dladdr(node->pc, &info);
         
        NSString * name = @(info.dli_sname);
         
        // 添加 _
        BOOL isObjc = [name hasPrefix:@"+["] || [name hasPrefix:@"-["];
        NSString * symbolName = isObjc ? name : [@"_" stringByAppendingString:name];
         
        //去重
        if (![symbolNames containsObject:symbolName]) {
            [symbolNames addObject:symbolName];
        }
    }
 
    //取反
    NSArray * symbolAry = [[symbolNames reverseObjectEnumerator] allObjects];
    NSLog(@"trace pc guard:\n---------------------------------------------------------------------------------\n");
    NSLog(@"%@",symbolAry);
    NSLog(@"---------------------------------------------------------------------------------");
     
    //将结果写入到文件
    NSString * funcString = [symbolAry componentsJoinedByString:@"\n"];
    NSString * filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"lb.order"];
    NSData * fileContents = [funcString dataUsingEncoding:NSUTF8StringEncoding];
    BOOL result = [[NSFileManager defaultManager] createFileAtPath:filePath contents:fileContents attributes:nil];
    if (result) {
        NSLog(@"%@",filePath);
    }else{
        NSLog(@"文件写入出错");
    }
}

@end
