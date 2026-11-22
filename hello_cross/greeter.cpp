#include "greeter.h"

std::string get_platform_greeting() {
#if defined(__linux__)
    return "Hello from Linux ELF binary (cross-compiled on macOS)!";
#elif defined(__APPLE__)
    return "Hello from native macOS Mach-O binary!";
#else
    return "Hello from unknown OS!";
#endif
}
