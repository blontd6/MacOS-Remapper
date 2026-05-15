#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <signal.h>
#include <termios.h>
#include <unistd.h>

#include <stdbool.h>
#include <sys/ioctl.h>

typedef enum {
  StateNormal,
  StateListeningOrig,
  StateListeningTarget,
  StateListeningDelete
} AppState;

static NSMutableDictionary<NSNumber *, NSNumber *> *keyMap = nil;
static _Atomic AppState currentState = StateNormal;
static _Atomic CGKeyCode tempOrigKey = 0;
static char lastMessage[256] = "";
static struct termios orig_termios;
static _Atomic int selectedOption = 0;
static _Atomic bool needsRedraw = true;

void reset_terminal_mode() {
  printf("\033[?1049l"); // screen buffer
  fflush(stdout);
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void sig_handler(int sig) {
  reset_terminal_mode();
  exit(0);
}

void sigwinch_handler(int sig) { needsRedraw = true; }

void saveMap() {
  NSMutableDictionary *saveDict = [NSMutableDictionary new];
  for (NSNumber *orig in keyMap) {
    saveDict[[orig stringValue]] = keyMap[orig];
  }
  [[NSUserDefaults standardUserDefaults] setObject:saveDict
                                            forKey:@"KeyMappings"];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

void loadMap() {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *saved = [defaults objectForKey:@"KeyMappings"];
  if (saved) {
    for (NSString *keyStr in saved) {
      keyMap[@([keyStr integerValue])] = saved[keyStr];
    }
  }
}

NSString *keyCodeToString(CGKeyCode keyCode) {
  TISInputSourceRef currentKeyboard = TISCopyCurrentKeyboardInputSource();
  CFDataRef layoutData = TISGetInputSourceProperty(
      currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
  if (!layoutData) {
    if (currentKeyboard)
      CFRelease(currentKeyboard);
    goto fallback;
  }
  const UCKeyboardLayout *keyboardLayout =
      (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);

  UInt32 deadKeyState = 0;
  UniChar chars[4];
  UniCharCount realLength;

  OSStatus status = UCKeyTranslate(
      keyboardLayout, keyCode, kUCKeyActionDown, 0, LMGetKbdType(),
      kUCKeyTranslateNoDeadKeysBit, &deadKeyState,
      sizeof(chars) / sizeof(chars[0]), &realLength, chars);
  if (currentKeyboard)
    CFRelease(currentKeyboard);

  if (status == noErr && realLength > 0) {
    NSString *str = [NSString stringWithCharacters:chars length:realLength];
    if ([str isEqualToString:@" "])
      return @"Space";
    if ([str isEqualToString:@"\r"])
      return @"Return";
    if ([str isEqualToString:@"\t"])
      return @"Tab";
    if ([str isEqualToString:@"\e"])
      return @"Escape";
    if ([str isEqualToString:@"\x19"])
      return @"BackTab";
    if ([str isEqualToString:@"\x08"] || [str isEqualToString:@"\x7F"])
      return @"Backspace";
    return [str uppercaseString];
  }

fallback:
  switch (keyCode) {
  case 36:
    return @"Return";
  case 48:
    return @"Tab";
  case 49:
    return @"Space";
  case 51:
    return @"Delete";
  case 53:
    return @"Escape";
  case 55:
    return @"Cmd";
  case 56:
    return @"Shift";
  case 57:
    return @"CapsLock";
  case 58:
    return @"Option";
  case 59:
    return @"Ctrl";
  case 123:
    return @"Left";
  case 124:
    return @"Right";
  case 125:
    return @"Down";
  case 126:
    return @"Up";
  default:
    return [NSString stringWithFormat:@"Key%d", keyCode];
  }
}

CGEventRef cgEventCallback(CGEventTapProxy proxy, CGEventType type,
                           CGEventRef event, void *refcon) {
  if (type != kCGEventKeyDown && type != kCGEventKeyUp &&
      type != kCGEventFlagsChanged)
    return event;

  CGKeyCode keycode =
      (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

  if (currentState != StateNormal) {
    if (type == kCGEventKeyDown) {
      if (currentState == StateListeningOrig) {
        tempOrigKey = keycode;
        snprintf(lastMessage, sizeof(lastMessage),
                 "Captured [%s]. Now press TARGET key...",
                 [keyCodeToString(keycode) UTF8String]);
        currentState = StateListeningTarget;
        needsRedraw = true;
      } else if (currentState == StateListeningTarget) {
        keyMap[@(tempOrigKey)] = @(keycode);
        saveMap();
        snprintf(lastMessage, sizeof(lastMessage),
                 "Success! Mapped [%s] -> [%s]",
                 [keyCodeToString(tempOrigKey) UTF8String],
                 [keyCodeToString(keycode) UTF8String]);
        currentState = StateNormal;
        needsRedraw = true;
      } else if (currentState == StateListeningDelete) {
        [keyMap removeObjectForKey:@(keycode)];
        saveMap();
        snprintf(lastMessage, sizeof(lastMessage),
                 "Success! Removed mapping for [%s]",
                 [keyCodeToString(keycode) UTF8String]);
        currentState = StateNormal;
        needsRedraw = true;
      }
    }
    return NULL; // Consume events while listening
  }

  if (type == kCGEventKeyDown || type == kCGEventKeyUp ||
      type == kCGEventFlagsChanged) {
    NSNumber *target = keyMap[@(keycode)];
    if (target) {
      CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode,
                                  [target intValue]);
    }
  }

  return event;
}

void clearScreen() { printf("\033[2J\033[H"); }

void printSeparator(char c, int cols) {
  for (int i = 0; i < cols - 1; i++) {
    putchar(c);
  }
  putchar('\n');
}

void printMenu(int opt) {
  struct winsize w;
  ioctl(STDOUT_FILENO, TIOCGWINSZ, &w);
  int cols = w.ws_col;
  int rows = w.ws_row;
  if (cols < 40)
    cols = 40;
  if (rows < 15)
    rows = 15;

  clearScreen();

  printSeparator('=', cols);

  const char *title = "MacOS KeyRemapper By Blon";
  int pad = (cols - (int)strlen(title)) / 2;
  for (int i = 0; i < pad; i++)
    putchar(' ');
  printf("%s\n", title);

  printSeparator('=', cols);
  printf("\n");

  const char *options[] = {"Add/Edit Keybind", "Delete Keybind", "Quit"};

  for (int i = 0; i < 3; i++) {
    if (i == opt) {
      printf("  > %s <\n", options[i]);
    } else {
      printf("    %s\n", options[i]);
    }
  }

  printf("\n");
  printSeparator('-', cols);
  printf(" Active Mappings:\n");

  int maxMappings = rows - 13;
  if (maxMappings < 1)
    maxMappings = 1;

  if (keyMap.count == 0) {
    printf("   (None)\n");
  } else {
    int printed = 0;
    for (NSNumber *key in keyMap) {
      if (printed >= maxMappings) {
        printf("   ... and %lu more\n",
               (unsigned long)(keyMap.count - printed));
        break;
      }
      NSString *origStr = keyCodeToString([key intValue]);
      NSString *targStr = keyCodeToString([keyMap[key] intValue]);
      printf("   %-8s ->  %-8s (codes: %d -> %d)\n", [origStr UTF8String],
             [targStr UTF8String], [key intValue], [keyMap[key] intValue]);
      printed++;
    }
  }

  // status bar
  printf("\033[%d;1H", rows - 2);
  printSeparator('=', cols);

  printf("\033[%d;1H", rows - 1);
  printf("\033[2K");
  if (strlen(lastMessage) > 0) {
    printf(" Status: %s\n", lastMessage);
  } else {
    printf(" Status: Waiting for input...\n");
  }

  fflush(stdout);
}

void runMenuLoop() {
  tcgetattr(STDIN_FILENO, &orig_termios);
  printf("\033[?1049h");
  fflush(stdout);
  atexit(reset_terminal_mode);
  signal(SIGINT, sig_handler);
  signal(SIGTERM, sig_handler);
  signal(SIGWINCH, sigwinch_handler);

  struct termios raw = orig_termios;
  raw.c_lflag &= ~(ECHO | ICANON);
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);

  int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);

  int lastState = -1;

  while (1) {
    if (currentState != lastState || needsRedraw) {
      printMenu(selectedOption);
      lastState = currentState;
      needsRedraw = false;
    }

    char c;
    if (read(STDIN_FILENO, &c, 1) == 1) {
      if (currentState == StateNormal) {
        if (c == '\033') {
          char seq[2];
          usleep(10000);
          if (read(STDIN_FILENO, &seq[0], 1) == 1 &&
              read(STDIN_FILENO, &seq[1], 1) == 1) {
            if (seq[0] == '[' || seq[0] == 'O') {
              if (seq[1] == 'A') {
                selectedOption--;
                if (selectedOption < 0)
                  selectedOption = 2;
                printMenu(selectedOption);
              } else if (seq[1] == 'B') { // Down
                selectedOption++;
                if (selectedOption > 2)
                  selectedOption = 0;
                printMenu(selectedOption);
              }
            }
          }
        } else if (c == '\n' || c == '\r') {
          if (selectedOption == 0) {
            snprintf(lastMessage, sizeof(lastMessage),
                     "Press the key you want to REPLACE (Origin)...");
            currentState = StateListeningOrig;
          } else if (selectedOption == 1) {
            snprintf(lastMessage, sizeof(lastMessage),
                     "Press the key to DELETE its mapping...");
            currentState = StateListeningDelete;
          } else if (selectedOption == 2) {
            printf("\nExiting...\n");
            exit(0);
          }
        } else if (c == 'q' || c == 'Q') {
          printf("\nExiting...\n");
          exit(0);
        }
      }
    }
    usleep(10000);
  }
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    keyMap = [NSMutableDictionary new];
    loadMap();

    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
      printf("Error: Accessibility permissions are required.\n");
      printf("Please grant accessibility permissions to your Terminal "
             "application in:\n");
      printf("System Settings -> Privacy & Security -> Accessibility.\n");
      return 1;
    }

    CGEventMask eventMask =
        (CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
         CGEventMaskBit(kCGEventFlagsChanged));
    CFMachPortRef eventTap = CGEventTapCreate(
        kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        eventMask, cgEventCallback, NULL);

    if (!eventTap) {
      printf("Failed to create event tap. You need to give accessibility "
             "permissions.\n");
      return 1;
    }

    CFRunLoopSourceRef runLoopSource =
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                       kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          runMenuLoop();
        });

    CFRunLoopRun();

    CFRelease(eventTap);
    CFRelease(runLoopSource);
  }
  return 0;
}
