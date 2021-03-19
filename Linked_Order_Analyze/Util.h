//
//  Util.h
//  Linked_Order_Analyze
//
//  Created by 李扬 on 2021/1/17.
//

#import <Foundation/Foundation.h>

@interface Util : NSObject

+ (unsigned long long)decimalFromHexStr:(NSString *)hexStr;

+ (NSString *)hexFromDecimal:(unsigned long long)decimal;

@end

