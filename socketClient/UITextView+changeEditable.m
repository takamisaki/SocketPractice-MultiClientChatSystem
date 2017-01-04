

#import "UITextView+changeEditable.h"

@implementation UITextView (changeEditable)

-(void)changeEditable:(BOOL)editable{
    
    self.editable = editable;
    
    if (editable) {
        self.backgroundColor = [UIColor whiteColor];
        self.textColor       = [UIColor blackColor];
    }else{
        self.backgroundColor = [UIColor brownColor];
        self.textColor       = [UIColor whiteColor];
    }
}
@end
