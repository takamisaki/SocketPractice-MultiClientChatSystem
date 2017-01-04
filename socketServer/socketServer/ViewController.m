#import "ViewController.h"
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>

//打印简洁化
#define NSLog(FORMAT, ...) fprintf(stderr,"%s\n",[[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);

@interface ViewController ()
//存储当前用户 socket和用户名 的数组, 每个成员都是个字典, 每个字典里都有 keys: name, socket
@property (nonatomic , strong) NSMutableArray<NSDictionary*> *allUsersArray;
@property (nonatomic , assign) int client_socket;
@end



@implementation ViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    self.allUsersArray = [NSMutableArray array];
    

    //SOCKET
    int server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket < 0) {
        NSLog(@"server_socket error");
        return;
    }
    
    
    //create and config server_address, prepare for binding
    struct sockaddr_in server_address;
    memset(&server_address, 0, sizeof(server_address));
    
    //set length, protocol, port, listening-IP
    server_address.sin_len         = sizeof(struct sockaddr_in);
    server_address.sin_family      = AF_INET;
    server_address.sin_port        = htons(9999);
    server_address.sin_addr.s_addr = inet_addr("127.0.0.1");


    //BIND server_socket and server_address for listen()
    int bind_result = bind(server_socket, (struct sockaddr*)&server_address,sizeof(server_address));
    if (bind_result < 0) {
        NSLog(@"bind error");
        return;
    }

    
    // LISTEN
    if (listen(server_socket, 5) < 0) {
        NSLog(@"listen error");
        return;
    }
    
    
#pragma mark - 死循环 accept 开始
    //不能让 accept 在子线程,这样在这个死循环大环境下会开启很多等待连接, accept 保持一个在运作就可以
    //但是好像放在主线程又会卡 UI, 反正这样服务器 UI 一直不 show
    while (1) {
        
        struct sockaddr_in client_address;
        socklen_t len = sizeof(client_address);
        NSLog(@"等待客户端连接...");
        
        int client_socket = accept(server_socket, (struct sockaddr*)&client_address, &len);
        if (client_socket < 0) {
            NSLog(@"client socket error");
            continue;
        }
        
        
#pragma mark * accept 成功, 子线程 accept 开始
        
        //如果 accept 成功, 把它放在子线程执行, 主线程依然在等待新的连接.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSLog(@"客户端连接成功");
            NSLog(@"IP: %s Port: %d",inet_ntoa(client_address.sin_addr),
                                     ntohs(client_address.sin_port));
            
            
#pragma mark ** 告诉客户端需要设置用户名
            
            if (write(client_socket, "#askName#现在需要设置用户名并发送", 128) < 0) {
                NSLog(@"[现在需要设置用户名并发送] 发送失败");
                return;
            }
            NSLog(@"[现在需要设置用户名并发送] 发送成功");
            sleep(1);
            
            
#pragma mark ** 发送全部用户名给客户端
            
            //如果用户名数组有成员
            if (self.allUsersArray.count) {
                //本消息的 prefix
                NSMutableString *allUserNameString = [NSMutableString new];
                [allUserNameString appendString:@"#allUsers#"];
                
                //读取用户名数组拼接成消息,每个用户名之间用##隔开(客户端用它来做分割)
                for (NSDictionary *dictTemp in self.allUsersArray) {
                    NSString *userName = [dictTemp valueForKey:@"userName"];
                    [allUserNameString appendFormat:@"%@##",userName];
                }
                
                //OC 字符串转 C 字符串
                char buffer[1024] = {0};
                char *pointer     = buffer;
                pointer           = (char *)[allUserNameString
                                             cStringUsingEncoding:NSUTF8StringEncoding];
                
                //发送
                if (write(client_socket, pointer, sizeof(buffer)) < 0) {
                    NSLog(@"[全部用户名] 发送失败");
                    return;
                }else{
                    NSLog(@"[全部用户名] 发送成功");
                }
            }
            
            //如果用户名数组无成员
            else{
                if(write(client_socket, "#allUsers#目前没有用户在线", 128)<0){
                    NSLog(@"[目前没有用户在线]发送失败");
                    return;
                }else{
                    NSLog(@"[目前没有用户在线]发送成功");
                }
            }
            
            
#pragma mark *** 新子线程, 死循环读写开始
            
            //死循环, 不然只跑一次, 没收到就错过了, 但是它不会空跑圈, 因为如果缓冲区无值, read 会阻塞它.
            //这个阻塞很合理, 反而不需要把这个 read 开子线程, 那就无意义了.
            //因为一个 read 针对一个客户端, 不需要 read 多次, 一个就够
            //按照思维导图案例的结构, 把死循环读写放在子线程里,
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                NSString *clientName = [NSString new];
                
                while (1) {
                    
                    //获取 read 的信息
                    NSString *msgFromClient = nil;
                    char buffer[1024]       = {0};
                    char *pointer           = buffer;
                    NSLog(@"服务器将读取客户端消息...");
                    
                    //read 开始阻塞
                    long readBytes = read(client_socket, pointer, sizeof(buffer));
                    
                    if (readBytes == -1) {
                        NSLog(@"服务器读取客户端消息失败");
                        continue;
                    }else{
                        buffer[readBytes] = '\0';
                        msgFromClient = [NSString stringWithCString:buffer
                                                           encoding:NSUTF8StringEncoding];
                        NSLog(@"收到客户端的原始消息是:%@",msgFromClient);
                    }
                    
                    
#pragma mark *** 客户端要关闭时的操作
                    
                    //确保此时用户已经输入过用户名, 不然服务器会群发下线通知"已下线"
                    if ([msgFromClient hasPrefix:@"#close#"] && clientName.length != 0) {
                        
                        char logOffBuffer[1024] = {0};
                        char *logOffPointer      = logOffBuffer;
                        NSString *logOffMsg      = [NSString stringWithFormat:@"#message#%@",
                                                    [msgFromClient substringFromIndex:7]];
                        logOffPointer            = (char *)[logOffMsg
                                                        cStringUsingEncoding:NSUTF8StringEncoding];
                        printf("服务器将群发:%s\n",logOffPointer);
                        
                        //移除该用户
                        NSString *clientSocketString = [NSString stringWithFormat:
                                                        @"%d",client_socket];
                        
                        
                        for (NSDictionary *dictTemp in self.allUsersArray) {
                            
                            NSString *userSocket = [dictTemp valueForKey:@"userSocket"];
                            
                            if ([userSocket isEqualToString:clientSocketString]) {
                                [self.allUsersArray removeObject:dictTemp];
                                NSLog(@"已经移除该用户");
                            }
                            break; //必须跳出,不然 for 循环会崩溃
                            
                        }
                        
                        //发送更新的全部用户名给所有用户(如果还有用户在线)
                        if (self.allUsersArray.count) {
                            
                            NSMutableString *allUserNameString = [NSMutableString new];
                            [allUserNameString appendString:@"#allUsers#"];
                            
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                                NSString *userName = [dictTemp valueForKey:@"userName"];
                                [allUserNameString appendFormat:@"%@##",userName];
                            }
                            
                            char buffer[1024] = {0};
                            char *pointer     = buffer;
                            pointer           = (char *)[allUserNameString
                                                         cStringUsingEncoding:NSUTF8StringEncoding];
                           
                            //遍历用户数组发送新的用户数组和离线用户的下线通知
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                                int socketTemp = [[dictTemp valueForKey:@"userSocket"] intValue];
                                write(socketTemp, pointer, sizeof(buffer));
                                sleep(2);
                                write(socketTemp, logOffPointer, sizeof(logOffBuffer));
                            }
                        }
                        break; //跳出死循环,然后 close
                    }
                    
                    
#pragma mark *** 客户端设置昵称时的操作
                    
                    else if ([msgFromClient hasPrefix:@"#setName#"]){
                        
                        //生成用户字典, 作为成员添加到数组
                        NSString *userName            = [msgFromClient substringFromIndex:9];
                        NSString *userSocket          = [NSString stringWithFormat:
                                                         @"%d",client_socket];
                        NSMutableDictionary *userDict = [NSMutableDictionary new];
                        [userDict setValue:userName     forKey:@"userName"];
                        [userDict setValue:userSocket   forKey:@"userSocket"];
                        
                        [self.allUsersArray addObject:userDict];
                        clientName = userName;
                        
                        //发送上线通知
                        NSString *logInMsg = [NSString stringWithFormat:@"#message#%@上线了",userName];
                        char logInBuffer[1024] = {0};
                        char *logInPointer = logInBuffer;
                        logInPointer = (char *)[logInMsg cStringUsingEncoding:NSUTF8StringEncoding];
                        
                        //发送更新的全部用户名给所有用户
                        if (self.allUsersArray.count) {
                            NSMutableString *allUserNameString = [NSMutableString new];
                            [allUserNameString appendString:@"#allUsers#"];
                            
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                                NSString *userName = [dictTemp valueForKey:@"userName"];
                                [allUserNameString appendFormat:@"%@##",userName];
                            }
                            
                            char buffer[1024] = {0};
                            char *pointer     = buffer;
                            pointer           = (char *)[allUserNameString
                                                         cStringUsingEncoding:NSUTF8StringEncoding];
                            
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                                int socketTemp = [[dictTemp valueForKey:@"userSocket"] intValue];
                                write(socketTemp, pointer, sizeof(buffer));
                                sleep(1);
                                write(socketTemp, logInPointer, sizeof(logInBuffer));
                            }
                        }
                    }
                    
                    
#pragma mark *** 客户端A 发给 B 消息操作
                    
                    else if ([msgFromClient hasPrefix:@"#toUser#"]){
                        
                        //截取出目标客户端名字, 发送的消息内容
                        NSRange  messageRange = [msgFromClient rangeOfString:@"#message#"];
                        NSRange  toUserRange  =  NSMakeRange(8, messageRange.location-8);
                        NSString *toUser      = [msgFromClient substringWithRange:toUserRange];
                        NSString *message     = [msgFromClient substringFromIndex:
                                                 messageRange.location+messageRange.length];
                        
                        char buffer[1024] = {0};
                        char *pointer     = buffer;
                        
                        //如果是群发
                        if ([toUser isEqualToString:@"EVERYONE"]) {
                            
                            NSString *fullMsg = [NSString stringWithFormat:
                                                @"#message#%@对[所有人]说:%@",clientName,message];
                            
                            pointer = (char *)[fullMsg cStringUsingEncoding:NSUTF8StringEncoding];
                            
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                            
                                int socketTemp = [[dictTemp valueForKey:@"userSocket"] intValue];
                                
                                if(write(socketTemp, pointer, sizeof(buffer)) < 0){
                                    NSLog(@"群发失败");
                                }else{
                                    NSLog(@"群发成功");
                                };
                            }
                        }
                        
                        //如果是发给指定用户
                        else{
                            NSString *fullMsg = [NSString stringWithFormat:
                                                 @"#message#%@对[你]说:%@",clientName,message];
                            
                            pointer = (char *)[fullMsg cStringUsingEncoding:NSUTF8StringEncoding];
                     
                            for (NSDictionary *dictTemp in self.allUsersArray) {
                            
                                if ([[dictTemp valueForKey:@"userName"] isEqualToString:toUser]) {
                                
                                    int socketTemp = [[dictTemp valueForKey:@"userSocket"]intValue];
                                    
                                    if(write(socketTemp, pointer, sizeof(buffer)) < 0){
                                        NSLog(@"[消息给 %@] 发送失败",toUser);
                                    }else{
                                        NSLog(@"[消息给 %@] 发送成功",toUser);
                                    };
                                    break;
                                }
                            }
                        }
                    }
                }
                
                close(client_socket);
                NSLog(@"服务器关闭了该客户端连接");
                NSLog(@"----------------------------------------");
            });
        });
    }
    
}

@end
