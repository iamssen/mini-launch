#import "ConfigStore.h"
#import <yaml.h>

static NSString * const CommandsKey = @"commands";
static NSString * const WebsitesKey = @"websites";
static NSString * const AppIconsKey = @"app_icons";

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
        static NSRegularExpression *nonString;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            nonString = [NSRegularExpression regularExpressionWithPattern:
                @"^(?:null|~|true|false|yes|no|on|off|[-+]?(?:[0-9][0-9_]*(?:\\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\\.[0-9]+|\\.inf|\\.nan)|0[xob][0-9a-f_]+)$"
                options:NSRegularExpressionCaseInsensitive error:nil];
        });
        if (!text.length || [nonString firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return nil;
    }
    return text;
}

// 섹션마다 다른 오류 문구와 값 검증을 한곳에 모읍니다. 검증은 문제 설명을 반환하고 정상이면 nil입니다.
typedef NSString *(*ValueCheck)(NSString *name, NSString *value);
typedef struct {
    __unsafe_unretained NSString *key, *mappingError, *entryError;
    ValueCheck check;
} Section;
static NSString *WebsiteProblem(NSString *name, NSString *value) {
    NSURL *website = [NSURL URLWithString:value];
    if (website.host.length && [@[@"http", @"https"] containsObject:website.scheme.lowercaseString]) return nil;
    return [NSString stringWithFormat:@"웹사이트 '%@'의 URL은 호스트가 있는 http 또는 https 주소여야 합니다.", name];
}
static const Section Sections[] = {
    {@"commands", @"commands는 이름과 명령 문자열의 매핑이어야 합니다.",
        @"명령 이름과 본문은 비어 있지 않은 문자열이어야 하며 이름을 중복할 수 없습니다.", NULL},
    {@"websites", @"websites는 이름과 웹사이트 URL의 매핑이어야 합니다.",
        @"웹사이트 이름과 URL은 비어 있지 않은 문자열이어야 하며 이름을 중복할 수 없습니다.", WebsiteProblem},
    {@"app_icons", @"app_icons는 앱 경로와 PNG 경로의 매핑이어야 합니다.",
        @"앱과 PNG 경로는 비어 있지 않은 문자열이어야 하며 앱 경로를 중복할 수 없습니다.", NULL},
};
static const Section *SectionForKey(NSString *key) {
    for (size_t i = 0; i < sizeof(Sections) / sizeof(*Sections); i++)
        if ([Sections[i].key isEqualToString:key]) return &Sections[i];
    return NULL;
}

// 아래 해석 함수는 문제 설명을 반환하며 정상이면 nil입니다.
// 한 섹션의 매핑을 작성 순서대로 entries에 담습니다.
static NSString *CollectEntries(yaml_document_t *document, yaml_node_t *mapping, const Section *section,
                                NSMutableArray<MLConfigEntry *> *entries) {
    if (!mapping || mapping->type != YAML_MAPPING_NODE) return section->mappingError;
    NSMutableSet *names = [NSMutableSet set];
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (yaml_node_pair_t *entry = mapping->data.mapping.pairs.start; entry < mapping->data.mapping.pairs.top; entry++) {
        NSString *name = Scalar(yaml_document_get_node(document, entry->key));
        NSString *value = Scalar(yaml_document_get_node(document, entry->value));
        if (![name stringByTrimmingCharactersInSet:space].length ||
            ![value stringByTrimmingCharactersInSet:space].length || [names containsObject:name] ||
            [name rangeOfString:@"\0"].location != NSNotFound || [value rangeOfString:@"\0"].location != NSNotFound) {
            return section->entryError;
        }
        NSString *problem = section->check ? section->check(name, value) : nil;
        if (problem) return problem;
        [names addObject:name];
        [entries addObject:[MLConfigEntry entryWithName:name value:value]];
    }
    return nil;
}
// 최상위 키를 모두 검사하고 요청한 섹션만 result에 담습니다.
static NSString *CollectSections(yaml_document_t *document, NSArray<NSString *> *sections,
                                 NSDictionary<NSString *, NSMutableArray<MLConfigEntry *> *> *result) {
    yaml_node_t *root = yaml_document_get_root_node(document);
    if (!root) return nil;
    if (root->type != YAML_MAPPING_NODE) return @"config.yml의 최상위 값은 매핑이어야 합니다.";
    NSMutableSet *rootKeys = [NSMutableSet set];
    for (yaml_node_pair_t *pair = root->data.mapping.pairs.start; pair < root->data.mapping.pairs.top; pair++) {
        NSString *key = Scalar(yaml_document_get_node(document, pair->key));
        if (!key || [rootKeys containsObject:key]) return @"설정 키는 중복되지 않는 문자열이어야 합니다.";
        [rootKeys addObject:key];
        const Section *section = [sections containsObject:key] ? SectionForKey(key) : NULL;
        if (!section) continue;
        NSString *problem = CollectEntries(document, yaml_document_get_node(document, pair->value), section, result[key]);
        if (problem) return problem;
    }
    return nil;
}
// YAML 문서가 하나인지 확인하며 파서 자원을 정리합니다.
static NSString *ParseSections(NSData *data, NSArray<NSString *> *sections,
                               NSDictionary<NSString *, NSMutableArray<MLConfigEntry *> *> *result) {
    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser)) return @"YAML 파서를 초기화하지 못했습니다.";
    yaml_parser_set_input_string(&parser, data.bytes, data.length);
    yaml_document_t document;
    NSString *problem = nil;
    if (!yaml_parser_load(&parser, &document)) {
        problem = [NSString stringWithFormat:@"config.yml %zu행: %s", parser.problem_mark.line + 1,
            parser.problem ?: "YAML 해석 실패"];
    } else {
        problem = CollectSections(&document, sections, result);
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
    return problem;
}

@implementation MLConfigEntry
+ (instancetype)entryWithName:(NSString *)name value:(NSString *)value {
    MLConfigEntry *entry = [self new];
    entry->_name = [name copy];
    entry->_value = [value copy];
    return entry;
}
- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:MLConfigEntry.class]) return NO;
    MLConfigEntry *other = object;
    return [_name isEqualToString:other->_name] && [_value isEqualToString:other->_value];
}
- (NSUInteger)hash { return _name.hash ^ _value.hash; }
@end

@implementation ConfigStore {
    NSURL *_url;
    dispatch_queue_t _queue;
}
- (instancetype)initWithURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    _url = url; _commands = @[]; _websites = @[];
    _queue = dispatch_queue_create("local.minilaunch.config", DISPATCH_QUEUE_SERIAL);
    return self;
}
+ (NSURL *)configurationURLInDirectory:(NSURL *)directory {
    return [directory URLByAppendingPathComponent:@"config.yml"];
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
         "# 명령이 끝난 뒤 창을 닫으려면 앞에 exec를 붙이세요.\n"
         "# 셸을 명령으로 대체하므로 Ctrl+C나 오류로 끝나도 창이 닫힙니다.\n"
         "# commands:\n"
         "#   \"설정 편집\": exec cursor ~/.config/fish/config.fish\n"
         "#   \"서버 접속\": exec ssh -t user@host\n"
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
+ (NSArray<MLConfigEntry *> *)commandsAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[CommandsKey] error:error][CommandsKey];
}
+ (NSArray<MLConfigEntry *> *)websitesAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[WebsitesKey] error:error][WebsitesKey];
}
+ (NSArray<MLConfigEntry *> *)appIconsAtURL:(NSURL *)url error:(NSError **)error {
    return [self entriesAtURL:url sections:@[AppIconsKey] error:error][AppIconsKey];
}
// 파일 부재와 빈 파일은 빈 목록이고, 읽기·형식 오류는 nil과 error입니다.
+ (NSDictionary<NSString *, NSArray<MLConfigEntry *> *> *)entriesAtURL:(NSURL *)url
        sections:(NSArray<NSString *> *)sections error:(NSError **)error {
    NSMutableDictionary<NSString *, NSMutableArray<MLConfigEntry *> *> *result = [NSMutableDictionary dictionary];
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
    NSString *problem = ParseSections(data, sections, result);
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
            NSDictionary *entries = [ConfigStore entriesAtURL:url sections:@[CommandsKey, WebsitesKey] error:&error];
            NSArray *commands = entries[CommandsKey];
            NSArray *websites = entries[WebsitesKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                ConfigStore *s = weakSelf;
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
