
#import "UIButton+changeState.h"

@implementation UIButton (changeState)
-(void)changeToEnabled:(BOOL)enabled{
    [self setEnabled:enabled];
    if (enabled) {
        [self setBackgroundColor:[UIColor greenColor]];
    } else {
        [self setBackgroundColor:[UIColor redColor]];
    }
}
@end
