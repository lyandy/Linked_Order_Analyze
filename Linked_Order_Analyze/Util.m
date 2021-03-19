//
//  Util.m
//  Linked_Order_Analyze
//
//  Created by 李扬 on 2021/1/17.
//

#import "Util.h"

@implementation Util

+ (unsigned long long)decimalFromHexStr:(NSString *)hexStr
{
    unsigned long long result = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexStr];

    [scanner setScanLocation:0]; // bypass '#' character
    [scanner scanHexLongLong:&result];
    
    return result;
}

+ (NSString *)hexFromDecimal:(unsigned long long)decimal
{
    return [NSString stringWithFormat:@"0x%llX", decimal];
}

@end
