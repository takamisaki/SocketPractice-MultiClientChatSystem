#import "ViewController.h"
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import "SVProgressHUD.h"
#import "UIButton+changeState.h"
#import "UITextView+changeEditable.h"

//打印简洁化
#define NSLog(FORMAT, ...) fprintf(stderr,"%s\n",[[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);

@interface ViewController ()
@property (weak,   nonatomic) IBOutlet UITextView *toName;            //对方昵称
@property (weak,   nonatomic) IBOutlet UITextView *msgReceived;       //显示收到的消息
@property (weak,   nonatomic) IBOutlet UITextView *msgSent;           //显示要发送的消息
@property (weak,   nonatomic) IBOutlet UITextView *showStatus;        //显示服务器状态
@property (weak,   nonatomic) IBOutlet UITextView *myName;            //显示自己昵称, 只可以设置一次
@property (weak,   nonatomic) IBOutlet UITextView *showAllNames;      //显示所有用户昵称, 不可编辑
@property (weak,   nonatomic) IBOutlet UIButton   *sendButton;
@property (weak,   nonatomic) IBOutlet UIButton   *connectButton;
@property (weak,   nonatomic) IBOutlet UIButton   *closeButton;
@property (assign, nonatomic) int                 serverSocket;       //服务器 socket
@property (copy,   nonatomic) NSString            *name;              //自己昵称
@property (assign, nonatomic) BOOL                recycleFlag;        //是否进行读写死循环
@property (strong, nonatomic) NSMutableArray      *allUsers;          //存储服务器传来的全部在线用户名
@end



@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.allUsers = [NSMutableArray new];
    
    NSLog(@"等待连接服务器...");
}


#pragma mark - connect 按钮方法
/*  1. socket(), connect()
 2. connect 成功后更新UI, 创建子线程, 在其中死循环 read
 3. 根据 read 到的 msg 的前缀进行不同操作
 */
- (IBAction)connectClicked:(id)sender {
    
    //SOCKET
    int server_socket = socket(AF_INET, SOCK_STREAM, 0);
    
    if (server_socket == -1) {
        [self configShowStatus:@"socket error" inColor:@"red"];
    }else{
        [self configShowStatus:@"socket succeed" inColor:@"green"];
        
        //配置 server_address
        struct sockaddr_in server_address;
        server_address.sin_len         = sizeof(struct sockaddr_in);
        server_address.sin_family      = AF_INET;
        server_address.sin_port        = htons(9999);
        server_address.sin_addr.s_addr = inet_addr("127.0.0.1");
        bzero(&(server_address.sin_zero), 8);
        
        //CONNECT
        int connectResult = connect(server_socket,
                                    (struct sockaddr*)&server_address,
                                    sizeof(struct sockaddr_in));
        if (connectResult != 0) {
            [self configShowStatus:@"连接失败" inColor:@"red"];
            return;
        }
        
        //成功后, 设置一下 UI 显示
        [self configShowStatus:@"已连接" inColor:@"green"];
        self.serverSocket = server_socket;
        
        //prepare for setting myName
        [self.myName        changeEditable:YES];
        [self.sendButton    changeToEnabled:YES];
        [self.closeButton   changeToEnabled:YES];
        [self.connectButton changeToEnabled:NO];
        
        self.recycleFlag = YES;
        
#pragma mark - 死循环读
        
        //read死循环, 开子线程是因为如果在主线程, UI 都会被卡住, 按钮都不显示了
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            while (self.recycleFlag) {
                
                NSLog(@"等待服务器消息...");
                
                NSString *nsMsg   = nil;
                char buffer[1024] = {0};
                char *pointer     = buffer;
                
                ssize_t readBytes = read(server_socket, pointer, sizeof(buffer));
                
                if (readBytes < 0) {
                    nsMsg = @"读取服务器消息失败";
                    NSLog(@"读取服务器消息失败");
                    continue;//因为不能不监听了,还得继续监听新的消息
                }else{
                    buffer[readBytes] = '\0';
                    nsMsg = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
                }
                NSLog(@"收到服务器的原始消息:%@",nsMsg);
                
                //根据前缀处理
                //如果是要求设置用户名的
                if ([nsMsg hasPrefix:@"#askName#"]) {
                    NSString *askNameMsg = [nsMsg substringFromIndex:9];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.msgReceived.text = askNameMsg;
                    });
                }
                
                //如果是服务器发来的全体用户名
                else if([nsMsg hasPrefix:@"#allUsers#"]){
                    
                    NSString *allUserMsg            = [nsMsg substringFromIndex:10];
                    self.allUsers                   = (NSMutableArray *)
                    [allUserMsg componentsSeparatedByString:@"##"];
                    NSMutableString *allUsersString = [NSMutableString new];
                    
                    for (NSString *userNameTemp in self.allUsers) {
                        //去除空字符串
                        if (userNameTemp.length == 0) {
                            [self.allUsers removeObject:userNameTemp];
                        }
                        //用户名尾部加回车
                        else {
                            [allUsersString appendFormat:@"%@\n",userNameTemp];
                        }
                    }
                    //在输出内容尾部加群发提示
                    [allUsersString appendString:@"EVERYONE(群发专用)"];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.showAllNames.text = allUsersString;
                    });
                }
                
                //如果是收到通信的消息
                else if ([nsMsg hasPrefix:@"#message#"]){
                    NSString *msg = [nsMsg substringFromIndex:9];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.msgReceived.text = msg;
                    });
                }
                
                //如果是收到谁下线的通知
                else if ([nsMsg hasPrefix:@"#close#"]){
                    NSString *msg = [nsMsg substringFromIndex:7];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.msgReceived.text = msg;
                    });
                }
            }
        });
    }
}


#pragma mark 关闭按钮点击事件
/*  1. 设置用户下线的通知内容, 发送给服务器, 服务器会群发给其他用户
 2. 客户端关闭连接, 更新 UI
 */
- (IBAction)closeClicked:(id)sender {
    
    NSString *myName   = self.myName.text;
    NSString *closeMsg = [NSString stringWithFormat:@"#close#%@马上下线",myName];
    char buffer[1024]  = {0};
    char *pointer      = buffer;
    pointer            = (char *)[closeMsg cStringUsingEncoding:NSUTF8StringEncoding];
    
    if(write(self.serverSocket, pointer, 1024) > 0){
        NSLog(@"客户端发送了[马上下线]给服务器");
        self.recycleFlag = NO;
    };
    if (close(self.serverSocket) == 0){
        NSLog(@"客户端关闭了连接");
        NSLog(@"------------------------------------");
    };
    
    //各种文本框清空和锁定
    self.showStatus.backgroundColor = [UIColor brownColor];
    self.showStatus.text   = nil;
    self.msgReceived.text  = nil;
    self.showAllNames.text = nil;
    self.myName.text       = nil;
    self.toName.text       = nil;
    self.msgSent.text      = nil;
    [self.myName        changeEditable:NO];
    [self.toName        changeEditable:NO];
    [self.msgSent       changeEditable:NO];
    [self.sendButton    changeToEnabled:NO];
    [self.closeButton   changeToEnabled:NO];
    [self.connectButton changeToEnabled:YES];
}


#pragma mark 发送按钮点击事件
/*  1. 判断用户昵称文本框能否编辑, 如果可以编辑就说明此时还没有发用户昵称给服务器, 就调用发昵称方法
 2. 如果不能编辑, 说明现在在正常聊天了, 调用发送消息方法, 服务器会处理并转发给你指定的用户
 */
- (IBAction)sendBtnClicked:(id)sender {
    
    //如果是发送 myName, (myName 文本框只在此时是可编辑的)
    if (self.myName.editable) {
        [self sendMyName:self.serverSocket];
    }
    //否则就是用户和对方的聊天
    else{
        [self sendMsgToServer:self.serverSocket];
    }
}


#pragma mark 发送用户名的方法
- (void)sendMyName:(int)server_socket{
    
    //不能不输入用户名
    if (self.myName.text.length == 0) {
        [self showHudWithString:@"请输入用户名"];
        return;
    }
    
    //验证输入的昵称是否和已有用户重名
    NSString *myName = self.myName.text;
    
    for (NSString *tempName in self.allUsers) {
        
        if ([tempName isEqualToString:myName]) {
            [self showHudWithString:@"不能和已上线用户重名"];
            break;
        }else if (![self stringIsLegal:myName]){
            [self showHudWithString:@"不能包含#号或者是 EVERYONE"];
            break;
        }
        
    }
    
    //把客户端的用户名发送给服务器, 更新 UI
    NSString *myNameMsg = [NSString stringWithFormat:@"#setName#%@",myName];
    char buffer[1024]   = {0};
    char *pointer       = buffer;
    pointer             = (char *)[myNameMsg cStringUsingEncoding:NSUTF8StringEncoding];
    
    if (write(server_socket, pointer, sizeof(buffer)) < 0) {
        [self showHudWithString:@"发送失败"];
    }else{
        [self showHudWithString:@"发送成功"];
        
        [self.myName      changeEditable:NO];
        [self.toName      changeEditable:YES];
        [self.msgSent     changeEditable:YES];
        [self.msgReceived setText:nil];
        [self.toName      setText:@"提示:如果发给所有人,输入EVERYONE"];
    }
}


#pragma mark 发送聊天信息的方法
- (void)sendMsgToServer:(int)server_socket{
    
    char buf[1024] = {0};
    char *pointer  = buf;
    
    //检查接收方字符串
    NSString *toNameString = self.toName.text;
    //接收方不能空白
    if (toNameString.length == 0) {
        [self showHudWithString:@"请输入接收用户名"];
        return;
    }
    //接收方必须在线
    if (![self toNameIsLegal:toNameString]){
        [self showHudWithString:@"该接收方无效"];
        return;
    }
    
    
    //检查发送的消息
    NSString *msgSentString = self.msgSent.text;
    //不能发送空白消息
    if (msgSentString.length == 0) {
        [self showHudWithString:@"请输入消息"];
        return;
    }else if (![self stringIsLegal:msgSentString]){
        [self showHudWithString:@"消息不能含有系统关键字"];
        return;
    }
    
    NSString *fullMsgSent = [NSString stringWithFormat:@"#toUser#%@#message#%@",
                             toNameString,msgSentString];
    NSLog(@"客户端要发送的消息是:%@",fullMsgSent);//打印看看
    pointer = (char *)[fullMsgSent cStringUsingEncoding:NSUTF8StringEncoding];
    
    //判断是否发送成功(可能需要服务器反馈 , 不能单基于客户端的消息判断)
    if (write(server_socket, pointer, sizeof(buf)) < 0) {
        [self showHudWithString:@"发送消息失败"];
    }else{
        [self showHudWithString:@"发送消息成功"];
    }
    
}

//判断字符串是否有可能系统的关键字重复
-(BOOL)stringIsLegal:(NSString *)string{
    if ([string containsString:@"#"]) {
        return NO;
    }else if ([string isEqualToString:@"EVERYONE"]){
        return NO;
    }
    return YES;
}

//判断消息接收方名字是否合法
-(BOOL)toNameIsLegal:(NSString *)name{
    for (NSString *nameTemp in self.allUsers) {
        if ([nameTemp isEqualToString:name]) {
            return YES;
        }
    }
    if([name isEqualToString:@"EVERYONE"]){
        return YES;
    }
    return NO;
}


//配置顶部显示连接状态的方法
-(void)configShowStatus:(NSString *)status inColor:(NSString *)color{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.showStatus.backgroundColor = [UIColor blackColor];
        
        if ([color isEqualToString:@"red"]) {
            self.showStatus.textColor = [UIColor redColor];
        }else{
            self.showStatus.textColor = [UIColor greenColor];
        }
        
        self.showStatus.text = status;
    });
}


//弹窗方法
- (void)showHudWithString: (NSString *)string {
    
    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack];
    [SVProgressHUD showWithStatus:string];
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC);
    dispatch_after(time, dispatch_get_main_queue(), ^{
        [SVProgressHUD dismiss];
    });
}

@end
