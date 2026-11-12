#import "CommandStore.h"
#import <yaml.h>

static NSError *ConfigError(NSString *message) {
    return [NSError errorWithDomain:@"MiniLaunch.Config" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}
static NSString *Scalar(yaml_node_t *node) {
    if (!node || node->type != YAML_SCALAR_NODE || strcmp((char *)node->tag, YAML_STR_TAG)) return nil;
    NSString *text = [[NSString alloc] initWithBytes:node->data.scalar.value
        length:node->data.scalar.length encoding:NSUTF8StringEncoding];
    // LibYAML은 암시적 타입을 해석하지 않으므로 설정의 문자열 검증을 보완합니다.
    if (node->data.scalar.style == YAML_PLAIN_SCALAR_STYLE) {
        NSRegularExpression *nonString = [NSRegularExpression regularExpressionWithPattern:
            @"^(?:null|~|true|false|yes|no|on|off|[-+]?(?:[0-9][0-9_]*(?:\\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\\.[0-9]+|\\.inf|\\.nan)|0[xob][0-9a-f_]+)$"
            options:NSRegularExpressionCaseInsensitive error:nil];
        if (!text.length || [nonString firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return nil;
    }
    return text;
}
@implementation CommandStore {
    NSURL *_url;
    dispatch_queue_t _queue;
}
- (instancetype)initWithURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    _url = url; _commands = @[]; _websites = @[];
    _queue = dispatch_queue_create("local.minilaunch.commands", DISPATCH_QUEUE_SERIAL);
    return self;
}
+ (BOOL)ensureConfigurationAtURL:(NSURL *)url error:(NSError **)error {
    BOOL directory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&directory]) {
        if (!directory) return YES;
        if (error) *error = ConfigError(@"config.yml 경로가 파일이 아닌 폴더입니다.");
        return NO;
    }
    NSString *initial =
        @"# MiniLaunch 웹사이트·터미널 명령 설정\n"
         "# 웹사이트 이름: http(s) URL 형식으로 작성한 순서대로 표시합니다.\n"
         "# 최근 Cursor 폴더와 명령 사이에 표시하며 기본 브라우저로 엽니다.\n"
         "# websites:\n"
         "#   \"dagu:local\": \"http://localhost:8480\"\n"
         "websites: {}\n"
         "\n"
         "# 명령 이름: 실행할 명령 형식으로 작성한 순서대로 표시합니다.\n"
         "# 클릭하면 iTerm의 새 창에서 실행하며, iTerm이 없으면 Terminal을 사용합니다.\n"
         "# 터미널 기본 프로필의 셸과 시작 위치를 그대로 사용합니다.\n"
         "# 아래 commands: {}를 예시처럼 바꾸고 저장한 뒤 런처를 다시 열거나 ⌘R을 누르세요.\n"
         "commands: {}\n"
         "\n"
         "# 한 줄 명령 예시:\n"
         "# commands:\n"
         "#   \"현재 위치\": pwd\n"
         "\n"
         "# 여러 줄 명령은 |를 사용하고 같은 들여쓰기를 유지하세요.\n"
         "# commands:\n"
         "#   \"작업 목록\": |\n"
         "#     cd Workspace\n"
         "#     ls -al\n"
         "# 이름은 중복할 수 없으며 이름과 명령은 비어 있지 않은 문자열이어야 합니다.\n"
         "\n# 메뉴 막대의 Apply App Icons에서 적용합니다.\n"
         "# app_icons:\n#   '~/Applications/Chrome Apps.localized/ChatGPT.app': 'icons/chatgpt.png'\n"
         "app_icons: {}\n";
    NSError *writeError = nil;
    if ([[initial dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:NSDataWritingWithoutOverwriting error:&writeError]) return YES;
    // 생성 직전에 다른 프로세스가 저장한 경우에도 그 파일을 보존합니다.
    if ([writeError.domain isEqualToString:NSCocoaErrorDomain] && writeError.code == NSFileWriteFileExistsError &&
        [NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&directory] && !directory) return YES;
    if (error) *error = writeError;
    return NO;
}
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)commandsAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[@"commands"] error:error][@"commands"];
}
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)websitesAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[@"websites"] error:error][@"websites"];
}
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)appIconsAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[@"app_icons"] error:error][@"app_icons"];
}
+ (NSDictionary *)entriesAtURL:(NSURL *)url sections:(NSArray<NSString *> *)sections error:(NSError **)error {
    NSMutableDictionary<NSString *, NSMutableArray *> *result = [NSMutableDictionary dictionary];
    for (NSString *section in sections) result[section] = [NSMutableArray array];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (!data) {
        if ([readError.domain isEqualToString:NSCocoaErrorDomain] && readError.code == NSFileReadNoSuchFileError) return result;
        if (error) *error = readError;
        return nil;
    }
    if (!data.length) return result;
    if (data.length > 256 * 1024) {
        if (error) *error = ConfigError(@"config.yml은 256KiB 이하여야 합니다.");
        return nil;
    }
    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser)) {
        if (error) *error = ConfigError(@"YAML 파서를 초기화하지 못했습니다.");
        return nil;
    }
    yaml_parser_set_input_string(&parser, data.bytes, data.length);
    yaml_document_t document;
    NSString *problem = nil;
    if (!yaml_parser_load(&parser, &document)) {
        problem = [NSString stringWithFormat:@"config.yml %zu행: %s", parser.problem_mark.line + 1,
            parser.problem ?: "YAML 해석 실패"];
    } else {
        yaml_node_t *root = yaml_document_get_root_node(&document);
        if (root && root->type != YAML_MAPPING_NODE) problem = @"config.yml의 최상위 값은 매핑이어야 합니다.";
        NSMutableSet *rootKeys = [NSMutableSet set];
        if (root && !problem) for (yaml_node_pair_t *pair = root->data.mapping.pairs.start;
            pair < root->data.mapping.pairs.top; pair++) {
            NSString *key = Scalar(yaml_document_get_node(&document, pair->key));
            if (!key || [rootKeys containsObject:key]) { problem = @"설정 키는 중복되지 않는 문자열이어야 합니다."; break; }
            [rootKeys addObject:key];
            if (![sections containsObject:key]) continue;
            BOOL icons = [key isEqualToString:@"app_icons"];
            BOOL websites = [key isEqualToString:@"websites"];
            NSString *mappingError = icons ? @"app_icons는 앱 경로와 PNG 경로의 매핑이어야 합니다."
                : (websites ? @"websites는 이름과 웹사이트 URL의 매핑이어야 합니다."
                : @"commands는 이름과 명령 문자열의 매핑이어야 합니다.");
            NSString *entryError = icons ? @"앱과 PNG 경로는 비어 있지 않은 문자열이어야 하며 앱 경로를 중복할 수 없습니다."
                : (websites ? @"웹사이트 이름과 URL은 비어 있지 않은 문자열이어야 하며 이름을 중복할 수 없습니다."
                : @"명령 이름과 본문은 비어 있지 않은 문자열이어야 하며 이름을 중복할 수 없습니다.");
            yaml_node_t *mapping = yaml_document_get_node(&document, pair->value);
            if (mapping->type != YAML_MAPPING_NODE) { problem = mappingError; break; }
            NSMutableSet *names = [NSMutableSet set];
            for (yaml_node_pair_t *entry = mapping->data.mapping.pairs.start; entry < mapping->data.mapping.pairs.top; entry++) {
                NSString *name = Scalar(yaml_document_get_node(&document, entry->key));
                NSString *value = Scalar(yaml_document_get_node(&document, entry->value));
                NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
                if (![name stringByTrimmingCharactersInSet:space].length ||
                    ![value stringByTrimmingCharactersInSet:space].length || [names containsObject:name] ||
                    [name rangeOfString:@"\0"].location != NSNotFound || [value rangeOfString:@"\0"].location != NSNotFound) {
                    problem = entryError; break;
                }
                if (websites) {
                    NSURL *website = [NSURL URLWithString:value];
                    if (!website.host.length || ![@[@"http", @"https"] containsObject:website.scheme.lowercaseString]) {
                        problem = [NSString stringWithFormat:@"웹사이트 '%@'의 URL은 호스트가 있는 http 또는 https 주소여야 합니다.", name];
                        break;
                    }
                }
                [names addObject:name];
                NSString *nameKey = icons ? @"app" : @"name";
                NSString *valueKey = icons ? @"png" : (websites ? @"url" : @"command");
                [result[key] addObject:@{nameKey: name, valueKey: value}];
            }
            if (problem) break;
        }
        yaml_document_delete(&document);
        if (!problem) {
            yaml_document_t extra;
            if (!yaml_parser_load(&parser, &extra)) problem = @"config.yml의 후속 내용을 해석하지 못했습니다.";
            else {
                if (yaml_document_get_root_node(&extra)) problem = @"config.yml에는 YAML 문서 하나만 작성해 주세요.";
                yaml_document_delete(&extra);
            }
        }
    }
    yaml_parser_delete(&parser);
    if (problem) { if (error) *error = ConfigError(problem); return nil; }
    return result;
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"설정 갱신은 메인 스레드에서 요청합니다.");
    if (_refreshing) return;
    _refreshing = YES;
    NSURL *url = _url;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSDictionary *entries = [CommandStore entriesAtURL:url sections:@[@"commands", @"websites"] error:&error];
            NSArray *commands = entries[@"commands"];
            NSArray *websites = entries[@"websites"];
            dispatch_async(dispatch_get_main_queue(), ^{
                CommandStore *s = weakSelf;
                if (!s) return;
                s->_refreshing = NO;
                BOOL changed = entries && (![s.commands isEqualToArray:commands] || ![s.websites isEqualToArray:websites]);
                BOOL errorChanged = ![(s.error.localizedDescription ?: @"") isEqualToString:error.localizedDescription ?: @""];
                if (entries) { s->_commands = [commands copy]; s->_websites = [websites copy]; }
                s->_error = error;
                if ((changed || errorChanged) && s.didRefresh) s.didRefresh();
            });
        }
    });
}
@end
